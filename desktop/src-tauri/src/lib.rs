mod panel_position;
mod tray;

pub mod clipboard;
pub mod transport;

use serde::Serialize;
use tauri::{Emitter, Manager, WindowEvent};
use tauri_plugin_autostart::MacosLauncher;

#[cfg(desktop)]
#[derive(Clone, Serialize)]
struct SingleInstancePayload {
    args: Vec<String>,
    cwd: String,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();

    #[cfg(desktop)]
    let builder = builder.plugin(tauri_plugin_single_instance::init(|app, args, cwd| {
        tray::show_panel(app, None);
        let _ = app.emit_to(
            "main",
            "single-instance",
            SingleInstancePayload { args, cwd },
        );
    }));

    builder
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec!["--autostart"]),
        ))
        .manage(tray::PanelState::default())
        .manage(transport::PocTransportRuntime::default())
        .setup(|app| {
            let tray_icon = tray::create_tray(app.handle())?;
            app.manage(tray_icon);
            clipboard::start_clipboard_monitor(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| match event {
            WindowEvent::CloseRequested { api, .. } if window.label() == "main" => {
                api.prevent_close();
                let _ = window.hide();
            }
            WindowEvent::Focused(false) if window.label() == "main" => {
                let state = window.app_handle().state::<tray::PanelState>();
                if state.handle_blur() {
                    let _ = window.hide();
                }
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            clipboard::read_clipboard_text,
            clipboard::write_clipboard_text,
            transport::get_poc_transport_status,
            transport::send_poc_clipboard_text,
            transport::start_poc_transport,
            transport::stop_poc_transport,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
