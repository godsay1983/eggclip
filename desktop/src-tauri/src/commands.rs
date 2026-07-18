use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, State};

use crate::{
    app_error::{AppErrorCode, AppErrorDto},
    pairing::PairingInvitationClipboardRuntime,
    transport::PocTransportRuntime,
};

fn command_result<T: Serialize>(
    result: Result<T, String>,
    code: AppErrorCode,
    retryable: bool,
    context: &'static str,
) -> Result<Value, AppErrorDto> {
    let value = result.map_err(|_| AppErrorDto::command(code, retryable, context))?;
    serde_json::to_value(value)
        .map_err(|_| AppErrorDto::command(AppErrorCode::InternalFailed, false, "command.serialize"))
}

#[tauri::command]
pub fn read_clipboard_text() -> Result<Value, AppErrorDto> {
    command_result(
        crate::clipboard::read_clipboard_text(),
        AppErrorCode::ClipboardReadFailed,
        true,
        "clipboard.read",
    )
}

#[tauri::command]
pub fn write_clipboard_text(text: String) -> Result<Value, AppErrorDto> {
    command_result(
        crate::clipboard::write_clipboard_text(text),
        AppErrorCode::ClipboardWriteFailed,
        true,
        "clipboard.write",
    )
}

#[tauri::command]
pub fn capture_clipboard_history_text(app: AppHandle, text: String) -> Result<Value, AppErrorDto> {
    command_result(
        crate::history::capture_clipboard_history_text(app, text),
        AppErrorCode::HistoryWriteFailed,
        false,
        "history.capture",
    )
}

#[tauri::command]
pub fn clear_clipboard_history(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::history::clear_clipboard_history(app),
        AppErrorCode::HistoryWriteFailed,
        false,
        "history.clear",
    )
}

#[tauri::command]
pub fn delete_clipboard_history_item(
    app: AppHandle,
    item_id: String,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::history::delete_clipboard_history_item(app, item_id),
        AppErrorCode::HistoryWriteFailed,
        false,
        "history.delete",
    )
}

#[tauri::command]
pub fn get_clipboard_history_used(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::history::get_clipboard_history_used(app),
        AppErrorCode::HistoryReadFailed,
        true,
        "history.count",
    )
}

#[tauri::command]
pub fn list_clipboard_history_preview(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::history::list_clipboard_history_preview(app),
        AppErrorCode::HistoryReadFailed,
        true,
        "history.list",
    )
}

#[tauri::command]
pub fn load_app_settings(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::settings::load_app_settings(app),
        AppErrorCode::SettingsReadFailed,
        true,
        "settings.load",
    )
}

#[tauri::command]
pub fn save_app_settings(
    app: AppHandle,
    settings: crate::sync::AppSettings,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::settings::save_app_settings(app, settings),
        AppErrorCode::SettingsSaveFailed,
        false,
        "settings.save",
    )
}

#[tauri::command]
pub fn load_local_device_identity(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::identity::load_local_device_identity(app),
        AppErrorCode::IdentityReadFailed,
        false,
        "identity.load",
    )
}

#[tauri::command]
pub fn create_local_sync_space(app: AppHandle, display_name: String) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::create_local_sync_space(app, display_name),
        AppErrorCode::SpaceWriteFailed,
        false,
        "space.create",
    )
}

#[tauri::command]
pub fn list_local_sync_spaces(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::list_local_sync_spaces(app),
        AppErrorCode::SpaceReadFailed,
        true,
        "space.list",
    )
}

#[tauri::command]
pub fn delete_local_sync_space(app: AppHandle, space_id: String) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::delete_local_sync_space(app, space_id),
        AppErrorCode::SpaceWriteFailed,
        false,
        "space.delete",
    )
}

#[tauri::command]
pub fn leave_member_sync_space(app: AppHandle, space_id: String) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::leave_member_sync_space(app, space_id),
        AppErrorCode::SpaceWriteFailed,
        false,
        "space.leave",
    )
}

#[tauri::command]
pub fn ensure_default_sync_space(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::ensure_default_sync_space(app),
        AppErrorCode::SpaceWriteFailed,
        false,
        "space.ensureDefault",
    )
}

#[tauri::command]
pub fn load_active_sync_space_id(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::load_active_sync_space_id(app),
        AppErrorCode::SpaceReadFailed,
        true,
        "space.loadActive",
    )
}

#[tauri::command]
pub fn select_active_sync_space(app: AppHandle, space_id: String) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::select_active_sync_space(app, space_id),
        AppErrorCode::SpaceWriteFailed,
        false,
        "space.selectActive",
    )
}

#[tauri::command]
pub fn run_space_hmac_diagnostic(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::run_space_hmac_diagnostic(app),
        AppErrorCode::SpaceReadFailed,
        false,
        "space.hmacDiagnostic",
    )
}

#[tauri::command]
pub fn create_pairing_invitation(
    app: AppHandle,
    runtime: State<'_, PairingInvitationClipboardRuntime>,
    space_id: String,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::create_pairing_invitation(app, runtime, space_id),
        AppErrorCode::SpaceWriteFailed,
        false,
        "pairing.invitationCreate",
    )
}

#[tauri::command]
pub fn copy_pairing_invitation(
    app: AppHandle,
    runtime: State<'_, PairingInvitationClipboardRuntime>,
    invitation_id: String,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::copy_pairing_invitation(app, runtime, invitation_id),
        AppErrorCode::ClipboardWriteFailed,
        false,
        "pairing.invitationCopy",
    )
}

#[tauri::command]
pub fn list_trusted_devices(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::list_trusted_devices(app),
        AppErrorCode::DeviceReadFailed,
        true,
        "device.list",
    )
}

#[tauri::command]
pub fn rename_trusted_device(
    app: AppHandle,
    device_id: String,
    display_name: String,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::pairing::rename_trusted_device(app, device_id, display_name),
        AppErrorCode::DeviceWriteFailed,
        false,
        "device.rename",
    )
}

#[tauri::command]
pub fn remove_trusted_device(app: AppHandle, device_id: String) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::remove_trusted_device(app, device_id),
        AppErrorCode::DeviceWriteFailed,
        false,
        "device.remove",
    )
}

#[tauri::command]
pub async fn start_poc_transport(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
    port: Option<u16>,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::start_poc_transport(app, runtime, port).await,
        AppErrorCode::NetworkUnavailable,
        true,
        "transport.start",
    )
}

#[tauri::command]
pub fn stop_poc_transport(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::stop_poc_transport(app, runtime),
        AppErrorCode::NetworkUnavailable,
        true,
        "transport.stop",
    )
}

#[tauri::command]
pub fn get_poc_transport_status(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::get_poc_transport_status(app, runtime),
        AppErrorCode::NetworkUnavailable,
        true,
        "transport.status",
    )
}

#[tauri::command]
pub fn send_poc_clipboard_text(
    runtime: State<'_, PocTransportRuntime>,
    text: String,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::send_poc_clipboard_text(runtime, text),
        AppErrorCode::SyncFailed,
        true,
        "transport.pocSend",
    )
}

#[tauri::command]
pub async fn connect_poc_peer(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
    host: String,
    port: u16,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::connect_poc_peer(app, runtime, host, port).await,
        AppErrorCode::NetworkUnavailable,
        true,
        "transport.pocConnect",
    )
}

#[tauri::command]
pub fn disconnect_all_poc_peers(
    app: AppHandle,
    runtime: State<'_, PocTransportRuntime>,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::disconnect_all_poc_peers(app, runtime),
        AppErrorCode::NetworkUnavailable,
        true,
        "transport.pocDisconnect",
    )
}

#[tauri::command]
pub fn load_poc_recent_endpoint(app: AppHandle) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::load_poc_recent_endpoint(app),
        AppErrorCode::NetworkUnavailable,
        true,
        "transport.pocRecent",
    )
}

#[tauri::command]
pub fn send_authenticated_clipboard_text(
    app: AppHandle,
    text: String,
) -> Result<Value, AppErrorDto> {
    command_result(
        crate::transport::send_authenticated_clipboard_text(app, text),
        AppErrorCode::SyncFailed,
        true,
        "transport.authenticatedSend",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_error_maps_internal_text_to_a_stable_safe_dto() {
        let error = command_result::<()>(
            Err("database path C:\\private and clipboard content".to_owned()),
            AppErrorCode::HistoryReadFailed,
            true,
            "history.list",
        )
        .expect_err("command should fail");

        let serialized = serde_json::to_string(&error).expect("error should serialize");
        assert_eq!(
            serialized,
            r#"{"code":"historyReadFailed","retryable":true,"params":{}}"#
        );
        assert!(!serialized.contains("private"));
        assert!(!serialized.contains("clipboard content"));
    }
}
