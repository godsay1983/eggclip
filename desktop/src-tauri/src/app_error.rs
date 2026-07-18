use std::collections::BTreeMap;

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum AppErrorCode {
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
}

impl AppErrorDto {
    pub fn new(code: AppErrorCode, retryable: bool) -> Self {
        Self {
            code,
            retryable,
            params: BTreeMap::new(),
        }
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
}
