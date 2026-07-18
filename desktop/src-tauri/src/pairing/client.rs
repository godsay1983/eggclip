use std::net::Ipv4Addr;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tauri::State;
use uuid::Uuid;
use zeroize::Zeroize;

use super::{join_runtime::PairingJoinRuntime, PAIRING_INVITATION_VERSION};
use crate::{
    app_error::{AppErrorCode, AppErrorDto},
    crypto::ED25519_PUBLIC_KEY_BYTES,
    settings::now_ms,
};

const INVITATION_PREFIX: &str = "eggclip://pair?p=";
const MAX_INVITATION_URI_BYTES: usize = 4096;
const MAX_INVITATION_PAYLOAD_BYTES: usize = 3072;
const MAX_ISSUER_DEVICE_NAME_CHARS: usize = 32;
const MAX_CONNECTION_ENDPOINTS: usize = 5;
const PAIRING_SECRET_BYTES: usize = 32;
const MAX_SAFE_JSON_INTEGER: u64 = 9_007_199_254_740_991;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingInvitationParseError {
    Empty,
    TooLarge,
    InvalidScheme,
    InvalidPayload,
    InvalidField(&'static str),
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingJoinAddressSummary {
    pub candidate_id: String,
    pub display_address: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingJoinAttemptSummary {
    pub attempt_id: String,
    pub issuer_device_name: String,
    pub issuer_short_fingerprint: String,
    pub space_short_id: String,
    pub expires_at_ms: u64,
    pub expires_in_seconds: u64,
    pub confirmation_code: String,
    pub addresses: Vec<PairingJoinAddressSummary>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PairingJoinEndpoint {
    pub host: Ipv4Addr,
    pub port: u16,
}

/// This model is intentionally not serializable or cloneable. It is owned by the
/// short-lived Rust join runtime and never crosses the Tauri boundary.
#[allow(dead_code)] // Remaining fields are consumed by the W2W-03 client handshake.
pub(crate) struct ParsedPairingInvitation {
    pub invitation_id: Uuid,
    pub space_id: Uuid,
    pub space_key_version: u32,
    pub issuer_device_name: String,
    pub issuer_device_id: Uuid,
    pub issuer_identity_public_key: String,
    pub pairing_secret: [u8; PAIRING_SECRET_BYTES],
    pub expires_at_ms: u64,
    pub confirmation_code: String,
    pub endpoints: Vec<PairingJoinEndpoint>,
}

impl Drop for ParsedPairingInvitation {
    fn drop(&mut self) {
        self.pairing_secret.zeroize();
    }
}

impl ParsedPairingInvitation {
    pub(crate) fn public_summary(
        &self,
        attempt_id: Uuid,
        now_ms: u64,
    ) -> PairingJoinAttemptSummary {
        let fingerprint: String = self.issuer_identity_public_key.chars().take(8).collect();
        let issuer_device_name = if self.issuer_device_name.is_empty() {
            format!("桌面端 #{fingerprint}")
        } else {
            self.issuer_device_name.clone()
        };
        PairingJoinAttemptSummary {
            attempt_id: attempt_id.to_string(),
            issuer_device_name,
            issuer_short_fingerprint: fingerprint,
            space_short_id: short_uuid(self.space_id),
            expires_at_ms: self.expires_at_ms,
            expires_in_seconds: self.expires_at_ms.saturating_sub(now_ms) / 1000,
            confirmation_code: self.confirmation_code.clone(),
            addresses: self
                .endpoints
                .iter()
                .enumerate()
                .map(|(index, endpoint)| PairingJoinAddressSummary {
                    candidate_id: format!("address-{}", index + 1),
                    display_address: mask_endpoint(endpoint),
                })
                .collect(),
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct IncomingPairingInvitationPayload {
    app: String,
    version: u16,
    kind: String,
    invitation_id: String,
    space_id: String,
    space_key_version: u32,
    #[serde(default)]
    issuer_device_name: Option<String>,
    issuer_device_id: String,
    issuer_identity_public_key: String,
    pairing_secret: String,
    expires_at_ms: u64,
    #[serde(default)]
    connection_hints: Option<IncomingPairingConnectionHints>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct IncomingPairingConnectionHints {
    transport: String,
    endpoints: Vec<IncomingPairingConnectionEndpoint>,
}

#[derive(Deserialize)]
struct IncomingPairingConnectionEndpoint {
    host: String,
    port: u16,
}

struct SensitiveBytes(Vec<u8>);

impl SensitiveBytes {
    fn as_slice(&self) -> &[u8] {
        &self.0
    }
}

impl Drop for SensitiveBytes {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

pub(crate) fn parse_pairing_invitation(
    invitation: String,
    now_ms: u64,
) -> Result<ParsedPairingInvitation, PairingInvitationParseError> {
    let invitation_bytes = SensitiveBytes(invitation.into_bytes());
    let invitation_text = std::str::from_utf8(invitation_bytes.as_slice())
        .map_err(|_| PairingInvitationParseError::InvalidPayload)?;
    let normalized = invitation_text.trim();
    if normalized.is_empty() {
        return Err(PairingInvitationParseError::Empty);
    }
    if normalized.len() > MAX_INVITATION_URI_BYTES {
        return Err(PairingInvitationParseError::TooLarge);
    }
    let encoded = normalized
        .strip_prefix(INVITATION_PREFIX)
        .ok_or(PairingInvitationParseError::InvalidScheme)?;
    let payload_bytes = SensitiveBytes(
        URL_SAFE_NO_PAD
            .decode(encoded)
            .map_err(|_| PairingInvitationParseError::InvalidPayload)?,
    );
    if payload_bytes.as_slice().len() > MAX_INVITATION_PAYLOAD_BYTES {
        return Err(PairingInvitationParseError::TooLarge);
    }
    let confirmation_code = confirmation_code(payload_bytes.as_slice());
    let payload: IncomingPairingInvitationPayload =
        serde_json::from_slice(payload_bytes.as_slice())
            .map_err(|_| PairingInvitationParseError::InvalidPayload)?;
    validate_pairing_payload(payload, now_ms, confirmation_code)
}

fn validate_pairing_payload(
    payload: IncomingPairingInvitationPayload,
    now_ms: u64,
    confirmation_code: String,
) -> Result<ParsedPairingInvitation, PairingInvitationParseError> {
    let IncomingPairingInvitationPayload {
        app,
        version,
        kind,
        invitation_id,
        space_id,
        space_key_version,
        issuer_device_name,
        issuer_device_id,
        issuer_identity_public_key,
        pairing_secret,
        expires_at_ms,
        connection_hints,
    } = payload;
    if app != "eggclip" {
        return Err(PairingInvitationParseError::InvalidField("app"));
    }
    if version != PAIRING_INVITATION_VERSION {
        return Err(PairingInvitationParseError::InvalidField("version"));
    }
    if kind != "pairingInvitation" {
        return Err(PairingInvitationParseError::InvalidField("kind"));
    }
    let invitation_id = Uuid::parse_str(&invitation_id)
        .map_err(|_| PairingInvitationParseError::InvalidField("invitationId"))?;
    let space_id = Uuid::parse_str(&space_id)
        .map_err(|_| PairingInvitationParseError::InvalidField("spaceId"))?;
    if space_key_version == 0 {
        return Err(PairingInvitationParseError::InvalidField("spaceKeyVersion"));
    }
    let issuer_device_name = normalize_device_name(issuer_device_name)?;
    let issuer_device_id = Uuid::parse_str(&issuer_device_id)
        .map_err(|_| PairingInvitationParseError::InvalidField("issuerDeviceId"))?;
    let identity_key = URL_SAFE_NO_PAD
        .decode(&issuer_identity_public_key)
        .map_err(|_| PairingInvitationParseError::InvalidField("issuerIdentityPublicKey"))?;
    if identity_key.len() != ED25519_PUBLIC_KEY_BYTES {
        return Err(PairingInvitationParseError::InvalidField(
            "issuerIdentityPublicKey",
        ));
    }
    let pairing_secret_encoded = SensitiveBytes(pairing_secret.into_bytes());
    let pairing_secret_decoded = SensitiveBytes(
        URL_SAFE_NO_PAD
            .decode(pairing_secret_encoded.as_slice())
            .map_err(|_| PairingInvitationParseError::InvalidField("pairingSecret"))?,
    );
    if pairing_secret_decoded.as_slice().len() != PAIRING_SECRET_BYTES {
        return Err(PairingInvitationParseError::InvalidField("pairingSecret"));
    }
    if expires_at_ms == 0 || expires_at_ms > MAX_SAFE_JSON_INTEGER {
        return Err(PairingInvitationParseError::InvalidField("expiresAtMs"));
    }
    if expires_at_ms <= now_ms {
        return Err(PairingInvitationParseError::Expired);
    }
    let endpoints = validate_connection_hints(connection_hints)?;
    let mut pairing_secret = [0u8; PAIRING_SECRET_BYTES];
    pairing_secret.copy_from_slice(pairing_secret_decoded.as_slice());
    Ok(ParsedPairingInvitation {
        invitation_id,
        space_id,
        space_key_version,
        issuer_device_name,
        issuer_device_id,
        issuer_identity_public_key,
        pairing_secret,
        expires_at_ms,
        confirmation_code,
        endpoints,
    })
}

fn normalize_device_name(value: Option<String>) -> Result<String, PairingInvitationParseError> {
    let Some(value) = value else {
        return Ok(String::new());
    };
    let normalized = value.trim();
    if normalized.is_empty() || normalized.chars().count() > MAX_ISSUER_DEVICE_NAME_CHARS {
        return Err(PairingInvitationParseError::InvalidField(
            "issuerDeviceName",
        ));
    }
    Ok(normalized.to_string())
}

fn validate_connection_hints(
    hints: Option<IncomingPairingConnectionHints>,
) -> Result<Vec<PairingJoinEndpoint>, PairingInvitationParseError> {
    let Some(hints) = hints else {
        return Ok(Vec::new());
    };
    if hints.transport != "ws"
        || hints.endpoints.is_empty()
        || hints.endpoints.len() > MAX_CONNECTION_ENDPOINTS
    {
        return Err(PairingInvitationParseError::InvalidField("connectionHints"));
    }
    let mut endpoints = Vec::with_capacity(hints.endpoints.len());
    for endpoint in hints.endpoints {
        let host = endpoint
            .host
            .parse::<Ipv4Addr>()
            .map_err(|_| PairingInvitationParseError::InvalidField("connectionHints"))?;
        if host.is_unspecified() || host.is_loopback() || endpoint.port == 0 {
            return Err(PairingInvitationParseError::InvalidField("connectionHints"));
        }
        endpoints.push(PairingJoinEndpoint {
            host,
            port: endpoint.port,
        });
    }
    Ok(endpoints)
}

fn confirmation_code(payload_bytes: &[u8]) -> String {
    let digest = Sha256::digest(payload_bytes);
    let value = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]) % 1_000_000;
    format!("{value:06}")
}

fn short_uuid(value: Uuid) -> String {
    value
        .simple()
        .to_string()
        .chars()
        .skip(24)
        .collect::<String>()
}

fn mask_endpoint(endpoint: &PairingJoinEndpoint) -> String {
    let octets = endpoint.host.octets();
    format!(
        "{}.{}.{}.*:{}",
        octets[0], octets[1], octets[2], endpoint.port
    )
}

#[tauri::command]
pub fn parse_pairing_join_invitation(
    runtime: State<'_, PairingJoinRuntime>,
    invitation: String,
) -> Result<PairingJoinAttemptSummary, AppErrorDto> {
    let timestamp = now_ms().map_err(|_| AppErrorDto::new(AppErrorCode::PairingFailed, false))?;
    runtime.begin(invitation, timestamp).map_err(join_error_dto)
}

#[tauri::command]
pub fn cancel_pairing_join_attempt(
    runtime: State<'_, PairingJoinRuntime>,
    attempt_id: String,
) -> Result<(), AppErrorDto> {
    runtime
        .discard(&attempt_id)
        .map(|_| ())
        .map_err(join_error_dto)
}

pub(crate) fn join_error_dto(error: super::join_runtime::PairingJoinRuntimeError) -> AppErrorDto {
    use super::join_runtime::PairingJoinRuntimeError;
    let code = match error {
        PairingJoinRuntimeError::Invitation(PairingInvitationParseError::Empty) => {
            AppErrorCode::PairingInvitationEmpty
        }
        PairingJoinRuntimeError::Invitation(PairingInvitationParseError::TooLarge) => {
            AppErrorCode::PairingInvitationTooLarge
        }
        PairingJoinRuntimeError::Invitation(PairingInvitationParseError::Expired)
        | PairingJoinRuntimeError::AttemptExpired => AppErrorCode::PairingInvitationExpired,
        PairingJoinRuntimeError::InvalidAttemptId | PairingJoinRuntimeError::AttemptMissing => {
            AppErrorCode::PairingInvitationUnavailable
        }
        PairingJoinRuntimeError::InvalidCandidate => AppErrorCode::PairingInvalidEndpoint,
        PairingJoinRuntimeError::Unavailable => AppErrorCode::PairingBusy,
        PairingJoinRuntimeError::Invitation(_) => AppErrorCode::PairingInvitationInvalid,
    };
    AppErrorDto::new(code, false)
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW_MS: u64 = 1_700_000_000_000;
    const HARMONY_FIXTURE_PAYLOAD: &str = concat!(
        r#"{"app":"eggclip","version":2,"kind":"pairingInvitation","invitationId":"018ff6f0-1111-7222-8333-123456789abc","spaceId":"018ff6ef-c394-7d08-8b99-4b7d10f2767a","spaceKeyVersion":1,"issuerDeviceId":"018ff6f0-0a3b-7815-a4db-3eb6e23d9338","issuerIdentityPublicKey":"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo","pairingSecret":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","expiresAtMs":1700000300000}"#
    );

    fn invitation(payload: &str) -> String {
        format!("{INVITATION_PREFIX}{}", URL_SAFE_NO_PAD.encode(payload))
    }

    fn base_payload() -> serde_json::Value {
        serde_json::json!({
            "app": "eggclip",
            "version": 2,
            "kind": "pairingInvitation",
            "invitationId": "018ff6f0-1111-7222-8333-123456789abc",
            "spaceId": "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
            "spaceKeyVersion": 1,
            "issuerDeviceName": " Windows B ",
            "issuerDeviceId": "018ff6f0-0a3b-7815-a4db-3eb6e23d9338",
            "issuerIdentityPublicKey": "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo",
            "pairingSecret": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "expiresAtMs": NOW_MS + 300_000,
            "connectionHints": {
                "transport": "ws",
                "endpoints": [
                    { "host": "192.168.10.24", "port": 4567 },
                    { "host": "10.0.0.8", "port": 4567 }
                ]
            }
        })
    }

    fn parse_value(
        value: serde_json::Value,
    ) -> Result<ParsedPairingInvitation, PairingInvitationParseError> {
        parse_pairing_invitation(invitation(&value.to_string()), NOW_MS)
    }

    #[test]
    fn parses_harmony_fixture_with_the_same_confirmation_code() {
        let parsed = parse_pairing_invitation(invitation(HARMONY_FIXTURE_PAYLOAD), NOW_MS)
            .expect("Harmony fixture should parse");
        assert_eq!(parsed.confirmation_code, "130762");
        assert_eq!(
            parsed.space_id.to_string(),
            "018ff6ef-c394-7d08-8b99-4b7d10f2767a"
        );
        assert_eq!(parsed.pairing_secret, [0u8; PAIRING_SECRET_BYTES]);
        let summary = parsed.public_summary(Uuid::nil(), NOW_MS);
        assert_eq!(summary.issuer_device_name, "桌面端 #11qYAYKx");
        assert_eq!(summary.issuer_short_fingerprint, "11qYAYKx");
        assert_eq!(summary.space_short_id, "10f2767a");
        assert!(summary.addresses.is_empty());
    }

    #[test]
    fn returns_only_masked_endpoint_summaries() {
        let parsed = parse_value(base_payload()).expect("invitation should parse");
        assert_eq!(parsed.issuer_device_name, "Windows B");
        let summary = parsed.public_summary(Uuid::now_v7(), NOW_MS);
        assert_eq!(summary.addresses[0].candidate_id, "address-1");
        assert_eq!(summary.addresses[0].display_address, "192.168.10.*:4567");
        let serialized = serde_json::to_string(&summary).expect("summary should serialize");
        assert!(!serialized.contains("192.168.10.24"));
        assert!(!serialized.contains("pairingSecret"));
        assert!(!serialized.contains("018ff6f0-0a3b-7815-a4db-3eb6e23d9338"));
        assert!(!serialized.contains("018ff6ef-c394-7d08-8b99-4b7d10f2767a"));
    }

    #[test]
    fn rejects_empty_wrong_scheme_invalid_payload_and_oversize_input() {
        assert_eq!(
            parse_pairing_invitation("  ".to_string(), NOW_MS).err(),
            Some(PairingInvitationParseError::Empty)
        );
        assert_eq!(
            parse_pairing_invitation("https://example.com".to_string(), NOW_MS).err(),
            Some(PairingInvitationParseError::InvalidScheme)
        );
        assert_eq!(
            parse_pairing_invitation(format!("{INVITATION_PREFIX}not-base64"), NOW_MS).err(),
            Some(PairingInvitationParseError::InvalidPayload)
        );
        assert_eq!(
            parse_pairing_invitation("x".repeat(MAX_INVITATION_URI_BYTES + 1), NOW_MS).err(),
            Some(PairingInvitationParseError::TooLarge)
        );
    }

    #[test]
    fn rejects_expired_unknown_version_and_invalid_core_fields() {
        let mut value = base_payload();
        value["expiresAtMs"] = serde_json::json!(NOW_MS);
        assert_eq!(
            parse_value(value).err(),
            Some(PairingInvitationParseError::Expired)
        );

        let mut value = base_payload();
        value["version"] = serde_json::json!(1);
        assert_eq!(
            parse_value(value).err(),
            Some(PairingInvitationParseError::InvalidField("version"))
        );

        for (field, replacement) in [
            ("invitationId", serde_json::json!("bad")),
            ("spaceId", serde_json::json!("bad")),
            ("issuerDeviceId", serde_json::json!("bad")),
            ("issuerIdentityPublicKey", serde_json::json!("AA")),
            ("pairingSecret", serde_json::json!("AA")),
        ] {
            let mut value = base_payload();
            value[field] = replacement;
            assert!(matches!(
                parse_value(value),
                Err(PairingInvitationParseError::InvalidField(_))
            ));
        }
    }

    #[test]
    fn rejects_invalid_or_excessive_connection_addresses() {
        for host in ["::1", "127.0.0.1", "0.0.0.0", "example.com"] {
            let mut value = base_payload();
            value["connectionHints"]["endpoints"] =
                serde_json::json!([{ "host": host, "port": 4567 }]);
            assert_eq!(
                parse_value(value).err(),
                Some(PairingInvitationParseError::InvalidField("connectionHints"))
            );
        }
        let mut value = base_payload();
        value["connectionHints"]["endpoints"] = serde_json::json!([
            { "host": "10.0.0.1", "port": 4567 },
            { "host": "10.0.0.2", "port": 4567 },
            { "host": "10.0.0.3", "port": 4567 },
            { "host": "10.0.0.4", "port": 4567 },
            { "host": "10.0.0.5", "port": 4567 },
            { "host": "10.0.0.6", "port": 4567 }
        ]);
        assert_eq!(
            parse_value(value).err(),
            Some(PairingInvitationParseError::InvalidField("connectionHints"))
        );
    }
}
