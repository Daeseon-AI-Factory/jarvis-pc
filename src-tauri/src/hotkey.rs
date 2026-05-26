use tauri::{AppHandle, Emitter};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

pub const TRIGGER_EVENT: &str = "screenbridge://trigger";

/// Register the v0.1 default shortcut (Opt/Alt + Space). Returns a boxed
/// error so the plugin's error type and tauri::Error can both flow through
/// `?` at call sites.
pub fn register_default(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let shortcut = Shortcut::new(Some(Modifiers::ALT), Code::Space);
    let handle = app.clone();
    app.global_shortcut().on_shortcut(shortcut, move |_app, _sc, event| {
        if event.state() == ShortcutState::Pressed {
            tracing::info!(target: "hotkey", "trigger pressed: Alt+Space");
            if let Err(e) = handle.emit(TRIGGER_EVENT, ()) {
                tracing::warn!(target: "hotkey", "emit trigger failed: {e}");
            }
        }
    })?;
    tracing::info!(target: "hotkey", "registered Alt+Space global shortcut");
    Ok(())
}
