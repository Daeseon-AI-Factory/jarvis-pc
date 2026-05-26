use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Emitter,
};

use crate::hotkey::TRIGGER_EVENT;

pub fn install(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let trigger = MenuItem::with_id(app, "trigger", "Trigger now", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&trigger, &settings, &quit])?;

    let mut builder = TrayIconBuilder::new().menu(&menu).on_menu_event(
        |app, event| match event.id().as_ref() {
            "trigger" => {
                tracing::info!(target: "tray", "trigger clicked");
                if let Err(e) = app.emit(TRIGGER_EVENT, ()) {
                    tracing::warn!(target: "tray", "emit trigger failed: {e}");
                }
            }
            "settings" => {
                // Wired up in Phase 6.3 (Settings UI). For now: log so the
                // click is observable in build.log.
                tracing::info!(target: "tray", "settings clicked (Phase 6.3 wires this)");
            }
            "quit" => {
                tracing::info!(target: "tray", "quit clicked");
                app.exit(0);
            }
            other => {
                tracing::warn!(target: "tray", "unknown menu id: {other}");
            }
        },
    );

    // Try the bundled default window icon first; if no window has been
    // created yet (early setup), the option will be None and the tray
    // shows without one until a window registers it.
    if let Some(icon) = app.default_window_icon().cloned() {
        builder = builder.icon(icon);
    }

    let _tray = builder.build(app)?;
    tracing::info!(target: "tray", "tray installed (Trigger now / Settings / Quit)");
    Ok(())
}
