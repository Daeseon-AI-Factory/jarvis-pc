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

// SPEC puts logs/build.log at the repo root; the crate lives in src-tauri/, so
// resolve relative to CARGO_MANIFEST_DIR at compile time. Dev-mode only —
// bundled macOS releases will need a different path (deferred to Phase 6).
fn build_log_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("CARGO_MANIFEST_DIR has a parent")
        .join("logs")
        .join("build.log")
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    init_logging();
    tracing::info!(target: "backend", "screenbridge starting");
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![greet, log_event])
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
