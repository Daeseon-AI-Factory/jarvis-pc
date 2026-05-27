use tauri::{AppHandle, Emitter};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

pub const TRIGGER_EVENT: &str = "sb-trigger";

/// Register the v0.1 default shortcut (Opt/Alt + Space). Returns a boxed
/// error so the plugin's error type and tauri::Error can both flow through
/// `?` at call sites.
pub fn register_default(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let shortcut = Shortcut::new(Some(Modifiers::ALT), Code::Space);
    let handle = app.clone();
    app.global_shortcut().on_shortcut(shortcut, move |_app, _sc, event| {
        if event.state() == ShortcutState::Pressed {
            // ⌥+Space 누른 시점 cursor 기록. analyze 시점엔 사용자가 panel로
            // cursor 옮긴 후라 capture가 panel monitor를 잡는 문제 방지.
            crate::capture::record_trigger_cursor();
            tracing::info!(target: "hotkey", "trigger pressed: Alt+Space");
            if let Err(e) = handle.emit(TRIGGER_EVENT, ()) {
                tracing::warn!(target: "hotkey", "emit trigger failed: {e}");
            }
        }
    })?;
    tracing::info!(target: "hotkey", "registered Alt+Space global shortcut");
    Ok(())
}
