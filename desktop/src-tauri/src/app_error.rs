use std::collections::BTreeMap;

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum AppErrorCode {
    ClipboardReadFailed,
    ClipboardWriteFailed,
    HistoryReadFailed,
    HistoryWriteFailed,
    SettingsReadFailed,
    SettingsSaveFailed,
    IdentityReadFailed,
    SpaceReadFailed,
    SpaceWriteFailed,
    DeviceReadFailed,
    DeviceWriteFailed,
    NetworkUnavailable,
    SyncFailed,
    InvalidInput,
    InternalFailed,
    PairingInvitationEmpty,
    PairingInvitationTooLarge,
    PairingInvitationInvalid,
    PairingInvitationExpired,
    PairingInvitationUnavailable,
    PairingIdentityMismatch,
    PairingCredentialFailed,
    PairingStorageFailed,
    PairingNetworkUnavailable,
    PairingAuthenticationFailed,
    PairingInvalidEndpoint,
    PairingBusy,
    PairingFailed,
}

/// Safe error object crossing the Tauri boundary. Domain errors and sensitive
/// details stay in Rust; the frontend renders a localized message from `code`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppErrorDto {
    pub code: AppErrorCode,
    pub retryable: bool,
    pub params: BTreeMap<String, String>,
    #[serde(skip)]
    internal_context: Option<&'static str>,
}

impl AppErrorDto {
    pub fn new(code: AppErrorCode, retryable: bool) -> Self {
        Self {
            code,
            retryable,
            params: BTreeMap::new(),
            internal_context: None,
        }
    }

    pub fn command(code: AppErrorCode, retryable: bool, internal_context: &'static str) -> Self {
        Self {
            code,
            retryable,
            params: BTreeMap::new(),
            internal_context: Some(internal_context),
        }
    }

    #[cfg(test)]
    pub(crate) fn internal_context(&self) -> Option<&'static str> {
        self.internal_context
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serialized_error_contains_only_stable_safe_fields() {
        let serialized = serde_json::to_string(&AppErrorDto::new(
            AppErrorCode::PairingAuthenticationFailed,
            false,
        ))
        .expect("error dto should serialize");

        assert_eq!(
            serialized,
            r#"{"code":"pairingAuthenticationFailed","retryable":false,"params":{}}"#
        );
        for forbidden in ["secret", "key", "content", "frame", "invitation"] {
            assert!(!serialized.to_ascii_lowercase().contains(forbidden));
        }
    }

    #[test]
    fn command_error_keeps_only_a_private_safe_diagnostic_category() {
        let error = AppErrorDto::command(AppErrorCode::HistoryReadFailed, true, "history.list");
        assert_eq!(error.internal_context(), Some("history.list"));
        assert_eq!(
            serde_json::to_string(&error).expect("command error should serialize"),
            r#"{"code":"historyReadFailed","retryable":true,"params":{}}"#
        );
    }
}
