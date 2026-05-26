pub mod capture;
pub mod dispatcher;
pub mod fixtures;
pub mod hotkey;
pub mod prompts;
pub mod sessions;
pub mod tray;

use std::path::PathBuf;
use std::sync::OnceLock;
use time::format_description::well_known::Iso8601;
use time::OffsetDateTime;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::fmt::{format::Writer, FmtContext, FormatEvent, FormatFields};
use tracing_subscriber::registry::LookupSpan;

static LOG_GUARD: OnceLock<WorkerGuard> = OnceLock::new();

struct BarFormatter;

impl<S, N> FormatEvent<S, N> for BarFormatter
where
    S: tracing::Subscriber + for<'a> LookupSpan<'a>,
    N: for<'a> FormatFields<'a> + 'static,
{
    fn format_event(
        &self,
        ctx: &FmtContext<'_, S, N>,
        mut writer: Writer<'_>,
        event: &tracing::Event<'_>,
    ) -> std::fmt::Result {
        let ts = OffsetDateTime::now_utc()
            .format(&Iso8601::DEFAULT)
            .unwrap_or_else(|_| "ts-err".to_string());
        write!(
            writer,
            "{} | runtime | {}:{} | ",
            ts,
            event.metadata().level().as_str().to_ascii_lowercase(),
            event.metadata().target()
        )?;
        ctx.field_format().format_fields(writer.by_ref(), event)?;
        writeln!(writer)
    }
}

// Crate lives in src-tauri/; the repo root (where .env, fixtures/, logs/ all
// sit) is its parent. Dev-mode only — bundled macOS releases will need a
// different path (deferred to Phase 6).
pub fn project_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("CARGO_MANIFEST_DIR has a parent")
        .to_path_buf()
}

fn build_log_path() -> PathBuf {
    project_root().join("logs").join("build.log")
}

fn parse_env_file_key(path: &std::path::Path, key: &str) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (k, v) = line.split_once('=')?;
        if k.trim() == key {
            let v = v.trim().trim_matches(|c: char| c == '"' || c == '\'');
            return Some(v.to_string());
        }
    }
    None
}

fn is_real_api_key(s: &str) -> bool {
    // Same placeholder taxonomy verify_key.sh uses.
    !s.is_empty()
        && s != "placeholder"
        && !s.contains("여기")
        && !s.contains("YOUR")
        && !s.contains("your-api-key")
}

/// Resolve ANTHROPIC_API_KEY from process env first, falling back to .env at
/// the repo root. Returns None for empty / placeholder values so callers can
/// gate on the result without re-checking the string.
pub fn anthropic_api_key() -> Option<String> {
    if let Ok(v) = std::env::var("ANTHROPIC_API_KEY") {
        if is_real_api_key(&v) {
            return Some(v);
        }
    }
    let env_path = project_root().join(".env");
    parse_env_file_key(&env_path, "ANTHROPIC_API_KEY").filter(|v| is_real_api_key(v))
}

/// Cheap check callers use to skip live API tests when the key is missing.
pub fn is_api_key_available() -> bool {
    anthropic_api_key().is_some()
}

fn init_logging() {
    let path = build_log_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .expect("open logs/build.log for append");
    let (nb, guard) = tracing_appender::non_blocking(file);
    let subscriber = tracing_subscriber::fmt()
        .with_writer(nb)
        .event_format(BarFormatter)
        .with_max_level(tracing::Level::INFO)
        .finish();
    // Best-effort: re-running tests within the same process tries to set the
    // global default twice; silently keep the first.
    let _ = tracing::subscriber::set_global_default(subscriber);
    let _ = LOG_GUARD.set(guard);
}

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[tauri::command]
fn log_event(level: String, msg: String) {
    match level.as_str() {
        "error" => tracing::error!(target: "frontend", "{}", msg),
        "warn" => tracing::warn!(target: "frontend", "{}", msg),
        _ => tracing::info!(target: "frontend", "{}", msg),
    }
}

#[tauri::command]
async fn analyze(
    app: tauri::AppHandle,
    instruction: String,
) -> Result<dispatcher::AnalysisResult, String> {
    use dispatcher::LLMDispatcher;
    use tauri::Manager;
    tracing::info!(target: "analyze", "begin: instr_len={}", instruction.len());
    let image = tauri::async_runtime::spawn_blocking(capture::capture_active_screen)
        .await
        .map_err(|e| format!("capture task join: {e}"))?
        .map_err(|e| format!("capture: {e}"))?;
    let dispatcher = dispatcher::ClaudeCliDispatcher::new();
    let result = dispatcher
        .analyze(image.clone(), instruction.clone())
        .await
        .map_err(|e| e.to_string())?;
    tracing::info!(
        target: "analyze",
        "done: state={:?}, next={:?}, coords={:?}",
        result.screen_state.as_deref(),
        result.next_action.as_deref(),
        result.coordinates
    );
    // Best-effort persistence; logging is enough on failure so the user
    // still gets the analysis result back.
    let mut result = result;
    match app.path().app_data_dir() {
        Ok(base) => {
            let sessions_dir = base.join("sessions");
            match sessions::save_session(&sessions_dir, &image, &instruction, &result) {
                Ok(dir) => {
                    result.session_dir = Some(dir.to_string_lossy().into_owned());
                }
                Err(e) => tracing::warn!(target: "sessions", "save failed: {e}"),
            }
        }
        Err(e) => tracing::warn!(target: "sessions", "app_data_dir unresolved: {e}"),
    }
    Ok(result)
}

#[tauri::command]
fn record_feedback(session_dir: String, value: String) -> Result<(), String> {
    sessions::record_feedback(std::path::Path::new(&session_dir), &value).map_err(|e| e.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    init_logging();
    tracing::info!(target: "backend", "screenbridge starting");
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            use tauri::{Emitter, Manager};
            // Belt + suspenders: tauri.conf.json visible:false is sometimes
            // not honored on first paint in dev mode, so we explicitly hide
            // both windows here. The overlay is also forced into
            // cursor-passthrough so a stray click can't dismiss it before
            // it ever has a payload to render.
            if let Some(w) = app.get_webview_window("trigger") {
                let _ = w.hide();
            }
            if let Some(w) = app.get_webview_window("overlay") {
                let _ = w.hide();
                let _ = w.set_ignore_cursor_events(true);
            }
            if let Err(e) = hotkey::register_default(app.handle()) {
                tracing::error!(target: "hotkey", "register failed: {e}");
            }
            if let Err(e) = tray::install(app.handle()) {
                tracing::error!(target: "tray", "install failed: {e}");
            }
            // Self-test (dev only): 5s after boot, fire sb-trigger so we can
            // see in build.log whether the React listener is wired without
            // the user having to press the hotkey.
            let handle_for_test = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                tracing::info!(target: "selftest", "emitting sb-trigger after 5s");
                if let Err(e) = handle_for_test.emit("sb-trigger", ()) {
                    tracing::warn!(target: "selftest", "emit failed: {e}");
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            greet,
            log_event,
            analyze,
            record_feedback
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod logging_tests {
    use super::*;
    use std::sync::Once;
    static INIT: Once = Once::new();

    #[test]
    fn writes_backend_and_frontend_lines() {
        let path = build_log_path();
        let before_len = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        INIT.call_once(init_logging);
        tracing::info!(target: "backend", "phase-1.1 smoke-backend");
        log_event("info".into(), "phase-1.1 smoke-frontend".into());
        // tracing-appender flushes asynchronously
        std::thread::sleep(std::time::Duration::from_millis(500));
        let after = std::fs::read_to_string(&path).expect("read build.log");
        let after_len = after.len() as u64;
        assert!(
            after_len > before_len,
            "no bytes appended: before={before_len} after={after_len}"
        );
        assert!(
            after.contains("phase-1.1 smoke-backend"),
            "backend line missing"
        );
        assert!(
            after.contains("phase-1.1 smoke-frontend"),
            "frontend line missing"
        );
    }
}
