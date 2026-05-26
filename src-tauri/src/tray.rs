use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager,
};

use crate::hotkey::TRIGGER_EVENT;

pub fn install(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let trigger = MenuItem::with_id(app, "trigger", "Trigger now", true, None::<&str>)?;
    let open_sessions = MenuItem::with_id(
        app,
        "open_sessions",
        "Open sessions folder",
        true,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let sep = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(app, &[&trigger, &sep, &open_sessions, &sep, &quit])?;

    let mut builder = TrayIconBuilder::new().menu(&menu).on_menu_event(
        |app, event| match event.id().as_ref() {
            "trigger" => {
                tracing::info!(target: "tray", "trigger clicked");
                if let Err(e) = app.emit(TRIGGER_EVENT, ()) {
                    tracing::warn!(target: "tray", "emit trigger failed: {e}");
                }
            }
            "open_sessions" => match app.path().app_data_dir() {
                Ok(base) => {
                    let dir = base.join("sessions");
                    if let Err(e) = std::fs::create_dir_all(&dir) {
                        tracing::warn!(target: "tray", "create sessions dir failed: {e}");
                    }
                    if let Err(e) = std::process::Command::new("open").arg(&dir).status() {
                        tracing::warn!(target: "tray", "open command failed: {e}");
                    } else {
                        tracing::info!(target: "tray", "opened sessions: {:?}", dir);
                    }
                }
                Err(e) => tracing::warn!(target: "tray", "app_data_dir unresolved: {e}"),
            },
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
