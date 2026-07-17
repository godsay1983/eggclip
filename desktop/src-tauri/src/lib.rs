mod panel_position;
mod tray;

pub mod clipboard;
pub mod crypto;
pub mod discovery;
pub mod history;
pub mod identity;
pub mod pairing;
pub mod protocol;
pub mod secret_store;
pub mod settings;
pub mod storage;
pub mod sync;
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
        .manage(clipboard::ClipboardRuntime::default())
        .manage(discovery::PocDiscoveryRuntime::default())
        .manage(transport::PocTransportRuntime::default())
        .manage(pairing::PairingJoinRuntime::default())
        .setup(|app| {
            pairing::reset_trusted_device_connection_states(app.handle())
                .map_err(std::io::Error::other)?;
            let (tray_icon, tray_status) = tray::create_tray(app.handle())?;
            app.manage(tray_icon);
            app.manage(tray_status);
            tray::refresh_status(app.handle());
            tray::start_status_task(app.handle().clone());
            clipboard::start_clipboard_monitor(app.handle().clone());
            pairing::start_pairing_invitation_expiry_task(app.handle().clone());
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
            history::capture_clipboard_history_text,
            history::clear_clipboard_history,
            history::delete_clipboard_history_item,
            history::get_clipboard_history_used,
            history::list_clipboard_history_preview,
            pairing::copy_pairing_invitation,
            pairing::client::cancel_pairing_join_attempt,
            pairing::create_local_sync_space,
            pairing::delete_local_sync_space,
            pairing::create_pairing_invitation,
            pairing::ensure_default_sync_space,
            pairing::list_local_sync_spaces,
            pairing::list_trusted_devices,
            pairing::load_active_sync_space_id,
            pairing::client::parse_pairing_join_invitation,
            pairing::run_space_hmac_diagnostic,
            pairing::rename_trusted_device,
            pairing::select_active_sync_space,
            identity::load_local_device_identity,
            settings::load_app_settings,
            settings::save_app_settings,
            transport::connect_poc_peer,
            transport::outbound::connect_trusted_peer,
            transport::disconnect_all_poc_peers,
            transport::get_poc_transport_status,
            transport::load_poc_recent_endpoint,
            transport::remove_trusted_device,
            transport::send_poc_clipboard_text,
            transport::send_authenticated_clipboard_text,
            transport::start_poc_transport,
            transport::stop_poc_transport,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
