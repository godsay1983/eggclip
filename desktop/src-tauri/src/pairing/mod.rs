use std::{fmt, path::Path};

#[cfg(test)]
use std::collections::HashMap;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use qrcode::{render::svg, EcLevel, QrCode};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    clipboard,
    crypto::{
        decode_base64url, derive_session_keys, encode_base64url, fixed_bytes,
        verify_ed25519_signature, SessionKeys, X25519Secret, ED25519_PUBLIC_KEY_BYTES,
        ED25519_SIGNATURE_BYTES, X25519_PUBLIC_KEY_BYTES, X25519_SHARED_SECRET_BYTES,
    },
    identity::{ensure_local_device_identity, IdentityError},
    protocol::{
        auth_transcript_hash_base64url, canonical_auth_transcript, parse_envelope,
        serialize_pre_auth_envelope, AuthProofPayload, AuthRole, AuthTranscriptInput, Capability,
        HelloPayload, MessageType, PreAuthEnvelope, ProtocolEnvelope, SignatureAlgorithm,
    },
    secret_store::{SecretBytesStore, SecretStoreError},
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{
            DeviceRepository, PairingInvitationRecord, PairingInvitationRepository,
            PairingInvitationState, SettingsRepository, SpaceRecord, SpaceRepository,
        },
    },
    sync::{content_hmac_digest, DeviceConnectionState, DeviceTrustState, Space, SpaceState},
};

pub const SPACE_KEY_BYTES: usize = 32;
pub const PAIRING_SECRET_BYTES: usize = 32;
pub const INITIAL_SPACE_KEY_VERSION: u32 = 1;
pub const PAIRING_INVITATION_TTL_MS: u64 = 5 * 60 * 1000;
pub const DEFAULT_SPACE_DISPLAY_NAME: &str = "默认空间";
const PAIRING_INVITATION_EXPIRY_SWEEP_SECONDS: u64 = 60;
const PAIRING_INVITATION_QR_MIN_DIMENSIONS: u32 = 224;
pub const ACTIVE_SYNC_SPACE_ID_KEY: &str = "activeSyncSpaceId";
pub const SPACE_HMAC_DIAGNOSTIC_TEXT: &str = "EggClip HUKS space key hmac self-test v1";

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncSpaceSummary {
    pub space_id: String,
    pub display_name: String,
    pub key_version: u32,
    pub space_key_ref: String,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncSpaceDeletionSummary {
    pub deleted_space_id: String,
    pub active_space_id: String,
    pub credential_deleted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceHmacDiagnosticSummary {
    pub space_id: String,
    pub space_display_name: String,
    pub confirmation_code: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrustedDeviceSummary {
    pub device_id: String,
    pub space_id: String,
    pub display_name: String,
    pub connection_state: String,
    pub short_fingerprint: String,
    pub paired_at_ms: Option<u64>,
    pub last_seen_at_ms: Option<u64>,
}

pub(crate) struct SpaceKeyRotationMaterial {
    pub device_id: Uuid,
    pub space_id: Uuid,
    pub key_version: u32,
    pub previous_key_ref: String,
    pub space_key: [u8; SPACE_KEY_BYTES],
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingInvitationSummary {
    pub invitation_id: String,
    pub space_id: String,
    pub space_display_name: String,
    pub invitation: String,
    pub qr_svg: String,
    pub expires_at_ms: u64,
    pub expires_in_seconds: u64,
    pub issuer_device_name: String,
    pub issuer_device_id: String,
    pub issuer_short_fingerprint: String,
    pub confirmation_code: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingServerHelloDraft {
    pub invitation_id: String,
    pub space_id: String,
    pub peer_device_id: String,
    pub peer_identity_public_key: String,
    pub peer_ephemeral_public_key: String,
    pub server_device_id: String,
    pub server_identity_public_key: String,
    pub server_ephemeral_public_key: String,
    pub pairing_context: String,
    pub server_hello_frame: String,
}

#[derive(Clone)]
pub struct PairingServerAuthProofInput {
    pub invitation_id: String,
    pub space_id: String,
    pub peer_device_id: String,
    pub peer_identity_public_key: String,
    pub peer_ephemeral_public_key: String,
    pub server_device_id: String,
    pub server_identity_public_key: String,
    pub server_ephemeral_public_key: String,
    pub pairing_context: String,
    pub server_ephemeral_secret: X25519Secret,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingServerAuthProofAccepted {
    pub invitation_id: String,
    pub space_id: String,
    pub peer_device_id: String,
    pub peer_identity_public_key: String,
    pub transcript_hash: String,
    pub transcript_salt: [u8; 32],
    pub shared_secret: [u8; X25519_SHARED_SECRET_BYTES],
    pub session_keys: SessionKeys,
    pub auth_ok_frame: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairingInvitationPayload {
    app: String,
    version: u16,
    kind: String,
    invitation_id: String,
    space_id: String,
    space_key_version: u32,
    issuer_device_name: String,
    issuer_device_id: String,
    issuer_identity_public_key: String,
    pairing_secret: String,
    expires_at_ms: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    connection_hints: Option<PairingConnectionHints>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PairingConnectionHints {
    pub transport: String,
    pub endpoints: Vec<PairingConnectionEndpoint>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PairingConnectionEndpoint {
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingError {
    Database(String),
    KeyStore(String),
    RandomUnavailable,
    InvalidDisplayName,
    InvalidSpaceId,
    MissingSpace,
    MissingSpaceKeyRef,
    MissingSpaceKey,
    LastSpaceCannotDelete,
    SpaceHasTrustedDevices,
    Identity(String),
    InvalidInvitation,
    InvitationMissing,
    InvitationExpired,
    InvitationConsumed,
    InvalidInvitationSecret,
    InvalidClientHello,
    InvalidAuthProof,
    AuthProofSignatureFailed,
    SessionKeyDerivationFailed,
    QrCode(String),
    Serialize(String),
}

impl fmt::Display for PairingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PairingError::Database(message) => write!(formatter, "database error: {message}"),
            PairingError::KeyStore(message) => write!(formatter, "key store error: {message}"),
            PairingError::RandomUnavailable => formatter.write_str("secure random unavailable"),
            PairingError::InvalidDisplayName => formatter.write_str("invalid space display name"),
            PairingError::InvalidSpaceId => formatter.write_str("invalid space id"),
            PairingError::MissingSpace => formatter.write_str("sync space missing"),
            PairingError::MissingSpaceKeyRef => formatter.write_str("space key reference missing"),
            PairingError::MissingSpaceKey => formatter.write_str("space key missing"),
            PairingError::LastSpaceCannotDelete => {
                formatter.write_str("the last sync space cannot be deleted")
            }
            PairingError::SpaceHasTrustedDevices => {
                formatter.write_str("sync space still has trusted devices")
            }
            PairingError::Identity(message) => write!(formatter, "identity error: {message}"),
            PairingError::InvalidInvitation => formatter.write_str("invalid pairing invitation"),
            PairingError::InvitationMissing => formatter.write_str("pairing invitation missing"),
            PairingError::InvitationExpired => formatter.write_str("pairing invitation expired"),
            PairingError::InvitationConsumed => formatter.write_str("pairing invitation consumed"),
            PairingError::InvalidInvitationSecret => {
                formatter.write_str("invalid pairing invitation secret")
            }
            PairingError::InvalidClientHello => formatter.write_str("invalid client hello"),
            PairingError::InvalidAuthProof => formatter.write_str("invalid auth proof"),
            PairingError::AuthProofSignatureFailed => {
                formatter.write_str("auth proof signature verification failed")
            }
            PairingError::SessionKeyDerivationFailed => {
                formatter.write_str("session key derivation failed")
            }
            PairingError::QrCode(message) => write!(formatter, "qr code error: {message}"),
            PairingError::Serialize(message) => write!(formatter, "serialize error: {message}"),
        }
    }
}

impl std::error::Error for PairingError {}

#[tauri::command]
pub fn create_local_sync_space(
    app: tauri::AppHandle,
    display_name: String,
) -> Result<SyncSpaceSummary, String> {
    let path = database_path(&app)?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    create_sync_space_at_path(&path, &mut store, &display_name, now_ms()?)
        .map_err(|error| format!("无法创建同步空间：{error}"))
}

#[tauri::command]
pub fn list_local_sync_spaces(app: tauri::AppHandle) -> Result<Vec<SyncSpaceSummary>, String> {
    let path = database_path(&app)?;
    list_sync_spaces_at_path(&path).map_err(|error| format!("无法读取同步空间：{error}"))
}

#[tauri::command]
pub fn delete_local_sync_space(
    app: tauri::AppHandle,
    space_id: String,
) -> Result<SyncSpaceDeletionSummary, String> {
    let space_id = Uuid::parse_str(&space_id).map_err(|_| "同步空间 ID 无效".to_owned())?;
    if crate::transport::has_authenticated_space(&app, space_id) {
        return Err("该同步空间仍有认证设备在线，请先断开或移除设备".to_owned());
    }
    let path = database_path(&app)?;
    let mut connection =
        open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    delete_sync_space_in_database(&mut connection, &mut store, space_id, now_ms()?).map_err(
        |error| match error {
            PairingError::LastSpaceCannotDelete => "至少需要保留一个同步空间".to_owned(),
            PairingError::SpaceHasTrustedDevices => {
                "该同步空间仍有关联的可信设备，请先移除设备".to_owned()
            }
            _ => format!("无法删除同步空间：{error}"),
        },
    )
}

#[tauri::command]
pub fn ensure_default_sync_space(app: tauri::AppHandle) -> Result<SyncSpaceSummary, String> {
    let path = database_path(&app)?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    ensure_default_sync_space_at_path(&path, &mut store, now_ms()?)
        .map_err(|error| format!("无法初始化默认同步空间：{error}"))
}

#[tauri::command]
pub fn load_active_sync_space_id(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let path = database_path(&app)?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    resolve_active_sync_space(&connection, now_ms()?)
        .map(|space_id| space_id.map(|value| value.to_string()))
        .map_err(|error| format!("无法读取活动同步空间：{error}"))
}

#[tauri::command]
pub fn select_active_sync_space(
    app: tauri::AppHandle,
    space_id: String,
) -> Result<SyncSpaceSummary, String> {
    let path = database_path(&app)?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    select_active_sync_space_in_database(&connection, &space_id, now_ms()?)
        .map_err(|error| format!("无法选择活动同步空间：{error}"))
}

#[tauri::command]
pub fn run_space_hmac_diagnostic(
    app: tauri::AppHandle,
) -> Result<SpaceHmacDiagnosticSummary, String> {
    let path = database_path(&app)?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    #[cfg(windows)]
    let store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let store = crate::secret_store::UnavailableSecretStore;
    run_space_hmac_diagnostic_in_database(&connection, &store, now_ms()?)
        .map_err(|error| format!("无法运行空间密钥 HMAC 诊断：{error}"))
}

#[tauri::command]
pub fn create_pairing_invitation(
    app: tauri::AppHandle,
    space_id: String,
) -> Result<PairingInvitationSummary, String> {
    let path = database_path(&app)?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    let mut summary = create_pairing_invitation_at_path(&path, &mut store, &space_id, now_ms()?)
        .map_err(|error| format!("无法生成配对邀请：{error}"))?;
    let endpoints = crate::transport::pairing_invitation_endpoints(&app);
    if !endpoints.is_empty() {
        let encoded = summary
            .invitation
            .strip_prefix("eggclip://pair?p=")
            .ok_or_else(|| "无法生成配对邀请：邀请格式无效".to_string())?;
        let bytes = URL_SAFE_NO_PAD
            .decode(encoded)
            .map_err(|_| "无法生成配对邀请：邀请编码无效".to_string())?;
        let mut payload: PairingInvitationPayload = serde_json::from_slice(&bytes)
            .map_err(|_| "无法生成配对邀请：邀请载荷无效".to_string())?;
        payload.connection_hints = Some(PairingConnectionHints {
            transport: "ws".to_string(),
            endpoints,
        });
        let payload_json =
            serde_json::to_vec(&payload).map_err(|error| format!("无法生成配对邀请：{error}"))?;
        summary.invitation = format!("eggclip://pair?p={}", URL_SAFE_NO_PAD.encode(&payload_json));
        summary.qr_svg = pairing_invitation_qr_svg(&summary.invitation)
            .map_err(|error| format!("无法生成配对邀请：{error}"))?;
        summary.confirmation_code = confirmation_code(&payload_json);
    }
    Ok(summary)
}

#[tauri::command]
pub fn copy_pairing_invitation(app: tauri::AppHandle, invitation: String) -> Result<(), String> {
    validate_pairing_invitation_uri(&invitation)
        .map_err(|error| format!("无法复制配对邀请：{error}"))?;
    clipboard::write_suppressed_clipboard_text(&app, invitation)
        .map_err(|error| format!("无法复制配对邀请：{error}"))
}

pub fn start_pairing_invitation_expiry_task(app: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(
            PAIRING_INVITATION_EXPIRY_SWEEP_SECONDS,
        ));
        loop {
            interval.tick().await;
            let Ok(timestamp_ms) = now_ms() else {
                continue;
            };
            let Ok(path) = database_path(&app) else {
                continue;
            };
            let _ = expire_pairing_invitations_at_path(&path, timestamp_ms);
        }
    });
}

pub fn create_sync_space_at_path<S: SecretBytesStore>(
    path: &Path,
    secret_store: &mut S,
    display_name: &str,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let mut connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    create_sync_space(&mut connection, secret_store, display_name, now_ms)
}

pub fn create_pairing_invitation_at_path<S: SecretBytesStore>(
    path: &Path,
    secret_store: &mut S,
    space_id: &str,
    now_ms: u64,
) -> Result<PairingInvitationSummary, PairingError> {
    let mut connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    create_pairing_invitation_for_space(&mut connection, secret_store, space_id, now_ms)
}

pub fn list_sync_spaces_at_path(path: &Path) -> Result<Vec<SyncSpaceSummary>, PairingError> {
    let connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    list_sync_spaces(&connection)
}

pub fn resolve_active_sync_space_at_path(
    path: &Path,
    updated_at: u64,
) -> Result<Option<Uuid>, PairingError> {
    let connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    resolve_active_sync_space(&connection, updated_at)
}

pub fn resolve_active_sync_space_target_at_path(
    path: &Path,
    updated_at: u64,
) -> Result<(Option<Uuid>, bool), PairingError> {
    let connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    let selected = resolve_active_sync_space(&connection, updated_at)?;
    if selected.is_some() {
        return Ok((selected, false));
    }
    Ok((None, selectable_space_ids(&connection)?.len() > 1))
}

pub fn expire_pairing_invitations_at_path(path: &Path, now_ms: u64) -> Result<usize, PairingError> {
    let connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    expire_pairing_invitations(&connection, now_ms)
}

pub fn ensure_default_sync_space_at_path<S: SecretBytesStore>(
    path: &Path,
    secret_store: &mut S,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let mut connection =
        open_database(path).map_err(|error| PairingError::Database(error.to_string()))?;
    ensure_default_sync_space_in_database(&mut connection, secret_store, now_ms)
}

pub fn ensure_default_sync_space_in_database<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let existing = list_sync_spaces(connection)?;
    if let Some(space) = existing.into_iter().next() {
        return Ok(space);
    }
    create_sync_space(connection, secret_store, DEFAULT_SPACE_DISPLAY_NAME, now_ms)
}

pub fn create_sync_space<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    display_name: &str,
    now_ms: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let display_name = normalize_space_display_name(display_name)?;
    let space_id = Uuid::now_v7();
    let key_version = INITIAL_SPACE_KEY_VERSION;
    let mut space_key = random_space_key()?;
    let space_key_ref = space_key_ref(space_id, key_version);

    secret_store
        .save_secret(&space_key_ref, &space_key)
        .map_err(pairing_secret_store_error)?;
    space_key.fill(0);

    let record = SpaceRecord {
        space: Space {
            space_id,
            display_name: display_name.clone(),
            key_version,
            state: SpaceState::Active,
            created_at: now_ms,
        },
        encrypted_space_key_ref: Some(space_key_ref.clone()),
        updated_at: now_ms,
    };
    SpaceRepository::new(connection)
        .upsert(&record)
        .map_err(|error| PairingError::Database(error.to_string()))?;

    Ok(SyncSpaceSummary {
        space_id: space_id.to_string(),
        display_name,
        key_version,
        space_key_ref,
        created_at_ms: now_ms,
    })
}

pub fn delete_sync_space_in_database<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    space_id: Uuid,
    updated_at: u64,
) -> Result<SyncSpaceDeletionSummary, PairingError> {
    let spaces = SpaceRepository::new(connection)
        .list()
        .map_err(|error| PairingError::Database(error.to_string()))?
        .into_iter()
        .filter(|record| {
            record.space.state == SpaceState::Active && record.encrypted_space_key_ref.is_some()
        })
        .collect::<Vec<_>>();
    let target = spaces
        .iter()
        .find(|record| record.space.space_id == space_id)
        .ok_or(PairingError::MissingSpace)?;
    if spaces.len() <= 1 {
        return Err(PairingError::LastSpaceCannotDelete);
    }
    let has_trusted_device = DeviceRepository::new(connection)
        .list_by_space(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .into_iter()
        .any(|record| {
            record.device.trust_state == DeviceTrustState::Trusted && record.revoked_at.is_none()
        });
    if has_trusted_device {
        return Err(PairingError::SpaceHasTrustedDevices);
    }
    let replacement_space_id = spaces
        .iter()
        .find(|record| record.space.space_id != space_id)
        .map(|record| record.space.space_id)
        .ok_or(PairingError::LastSpaceCannotDelete)?;
    let active_space_id = SettingsRepository::new(connection)
        .get(ACTIVE_SYNC_SPACE_ID_KEY)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .and_then(|value| Uuid::parse_str(&value).ok());
    let key_ref = target
        .encrypted_space_key_ref
        .clone()
        .ok_or(PairingError::MissingSpaceKeyRef)?;

    let transaction = connection
        .transaction()
        .map_err(|error| PairingError::Database(error.to_string()))?;
    transaction
        .execute(
            "DELETE FROM spaces WHERE space_id = ?1",
            rusqlite::params![space_id.to_string()],
        )
        .map_err(|error| PairingError::Database(error.to_string()))?;
    let next_active_space_id = if active_space_id == Some(space_id) {
        SettingsRepository::new(&transaction)
            .set(
                ACTIVE_SYNC_SPACE_ID_KEY,
                &replacement_space_id.to_string(),
                updated_at,
            )
            .map_err(|error| PairingError::Database(error.to_string()))?;
        replacement_space_id
    } else {
        active_space_id.unwrap_or(replacement_space_id)
    };
    transaction
        .commit()
        .map_err(|error| PairingError::Database(error.to_string()))?;

    Ok(SyncSpaceDeletionSummary {
        deleted_space_id: space_id.to_string(),
        active_space_id: next_active_space_id.to_string(),
        credential_deleted: secret_store.delete_secret(&key_ref).is_ok(),
    })
}

pub fn load_space_key<S: SecretBytesStore>(
    connection: &Connection,
    secret_store: &S,
    space_id: Uuid,
) -> Result<[u8; SPACE_KEY_BYTES], PairingError> {
    let space = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::MissingSpaceKeyRef)?;
    let space_key_ref = space
        .encrypted_space_key_ref
        .ok_or(PairingError::MissingSpaceKeyRef)?;
    let Some(secret) = secret_store
        .load_secret(&space_key_ref)
        .map_err(pairing_secret_store_error)?
    else {
        return Err(PairingError::MissingSpaceKey);
    };
    if secret.len() != SPACE_KEY_BYTES {
        return Err(PairingError::KeyStore(
            SecretStoreError::InvalidLength {
                actual: secret.len(),
                expected: SPACE_KEY_BYTES,
            }
            .to_string(),
        ));
    }
    let mut key = [0u8; SPACE_KEY_BYTES];
    key.copy_from_slice(&secret);
    Ok(key)
}

pub fn list_sync_spaces(connection: &Connection) -> Result<Vec<SyncSpaceSummary>, PairingError> {
    let records = SpaceRepository::new(connection)
        .list()
        .map_err(|error| PairingError::Database(error.to_string()))?;
    Ok(records
        .into_iter()
        .filter(|record| {
            record.space.state == SpaceState::Active && record.encrypted_space_key_ref.is_some()
        })
        .map(|record| SyncSpaceSummary {
            space_id: record.space.space_id.to_string(),
            display_name: record.space.display_name,
            key_version: record.space.key_version,
            space_key_ref: record.encrypted_space_key_ref.unwrap_or_default(),
            created_at_ms: record.space.created_at,
        })
        .collect())
}

#[tauri::command]
pub fn list_trusted_devices(app: tauri::AppHandle) -> Result<Vec<TrustedDeviceSummary>, String> {
    let path = database_path(&app)?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    let mut devices =
        list_trusted_devices_in_database(&connection).map_err(|error| error.to_string())?;
    let online_device_ids = crate::transport::authenticated_device_ids(&app);
    for device in &mut devices {
        device.connection_state = Uuid::parse_str(&device.device_id)
            .ok()
            .filter(|device_id| online_device_ids.contains(device_id))
            .map(|_| "online".to_owned())
            .unwrap_or_else(|| "offline".to_owned());
    }
    Ok(devices)
}

#[tauri::command]
pub fn rename_trusted_device(
    app: tauri::AppHandle,
    device_id: String,
    display_name: String,
) -> Result<TrustedDeviceSummary, String> {
    let path = database_path(&app)?;
    let connection = open_database(path).map_err(|error| format!("无法打开本地数据库：{error}"))?;
    rename_trusted_device_in_database(&connection, &device_id, &display_name)
        .map_err(|error| error.to_string())
}

pub fn list_trusted_devices_in_database(
    connection: &Connection,
) -> Result<Vec<TrustedDeviceSummary>, PairingError> {
    let local_device_id = SettingsRepository::new(connection)
        .get(crate::storage::repositories::LOCAL_DEVICE_ID_KEY)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .and_then(|value| Uuid::parse_str(&value).ok());
    let mut summaries = Vec::new();
    for space in SpaceRepository::new(connection)
        .list()
        .map_err(|error| PairingError::Database(error.to_string()))?
    {
        for record in DeviceRepository::new(connection)
            .list_by_space(space.space.space_id)
            .map_err(|error| PairingError::Database(error.to_string()))?
        {
            if Some(record.device.device_id) == local_device_id
                || record.device.trust_state != DeviceTrustState::Trusted
                || record.revoked_at.is_some()
            {
                continue;
            }
            summaries.push(trusted_device_summary(&record));
        }
    }
    summaries.sort_by(|left, right| left.display_name.cmp(&right.display_name));
    Ok(summaries)
}

pub fn rename_trusted_device_in_database(
    connection: &Connection,
    device_id: &str,
    display_name: &str,
) -> Result<TrustedDeviceSummary, PairingError> {
    let device_id = Uuid::parse_str(device_id).map_err(|_| PairingError::InvalidInvitation)?;
    let normalized = normalize_device_display_name(display_name)?;
    let repository = DeviceRepository::new(connection);
    let mut record = repository
        .get(device_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::InvalidInvitation)?;
    if record.device.trust_state != DeviceTrustState::Trusted || record.revoked_at.is_some() {
        return Err(PairingError::InvalidInvitation);
    }
    record.device.display_name = normalized;
    repository
        .upsert(&record)
        .map_err(|error| PairingError::Database(error.to_string()))?;
    Ok(trusted_device_summary(&record))
}

pub(crate) fn revoke_device_and_rotate_space_key<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    device_id: Uuid,
    revoked_at: u64,
) -> Result<SpaceKeyRotationMaterial, PairingError> {
    let current_device = DeviceRepository::new(connection)
        .get(device_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::InvalidInvitation)?;
    if current_device.device.trust_state != DeviceTrustState::Trusted
        || current_device.revoked_at.is_some()
    {
        return Err(PairingError::InvalidInvitation);
    }
    let space_id = current_device.device.space_id;
    let current_space = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::MissingSpace)?;
    let previous_key_ref = current_space
        .encrypted_space_key_ref
        .clone()
        .ok_or(PairingError::MissingSpaceKeyRef)?;
    let key_version = current_space
        .space
        .key_version
        .checked_add(1)
        .ok_or(PairingError::InvalidSpaceId)?;
    let mut space_key = random_space_key()?;
    let next_key_ref = space_key_ref(space_id, key_version);
    if let Err(error) = secret_store.save_secret(&next_key_ref, &space_key) {
        space_key.fill(0);
        return Err(pairing_secret_store_error(error));
    }

    let rotation_result = (|| -> Result<(), PairingError> {
        let transaction = connection
            .transaction()
            .map_err(|error| PairingError::Database(error.to_string()))?;
        let mut revoked_device = current_device;
        revoked_device.device.trust_state = DeviceTrustState::Revoked;
        revoked_device.device.connection_state = DeviceConnectionState::Offline;
        revoked_device.revoked_at = Some(revoked_at);
        DeviceRepository::new(&transaction)
            .upsert(&revoked_device)
            .map_err(|error| PairingError::Database(error.to_string()))?;
        // Clipboard ciphertext and HMAC digests are bound to the previous space key.
        // v1 deliberately clears this bounded history during rotation instead of
        // retaining an undecryptable or unverifiable mixed-key history.
        transaction
            .execute(
                "DELETE FROM clipboard_items WHERE space_id = ?1",
                rusqlite::params![space_id.to_string()],
            )
            .map_err(|error| PairingError::Database(error.to_string()))?;
        transaction
            .execute(
                "DELETE FROM sync_heads WHERE space_id = ?1",
                rusqlite::params![space_id.to_string()],
            )
            .map_err(|error| PairingError::Database(error.to_string()))?;
        let mut rotated_space = current_space;
        rotated_space.space.key_version = key_version;
        rotated_space.encrypted_space_key_ref = Some(next_key_ref.clone());
        rotated_space.updated_at = revoked_at;
        SpaceRepository::new(&transaction)
            .upsert(&rotated_space)
            .map_err(|error| PairingError::Database(error.to_string()))?;
        transaction
            .commit()
            .map_err(|error| PairingError::Database(error.to_string()))
    })();
    if let Err(error) = rotation_result {
        space_key.fill(0);
        let _ = secret_store.delete_secret(&next_key_ref);
        return Err(error);
    }

    Ok(SpaceKeyRotationMaterial {
        device_id,
        space_id,
        key_version,
        previous_key_ref,
        space_key,
    })
}

fn trusted_device_summary(
    record: &crate::storage::repositories::DeviceRecord,
) -> TrustedDeviceSummary {
    let digest = Sha256::digest(record.device.identity_public_key_ref.as_bytes());
    TrustedDeviceSummary {
        device_id: record.device.device_id.to_string(),
        space_id: record.device.space_id.to_string(),
        display_name: record.device.display_name.clone(),
        connection_state: match record.device.connection_state {
            DeviceConnectionState::Online => "online",
            DeviceConnectionState::Connecting => "connecting",
            DeviceConnectionState::AuthFailed => "authFailed",
            DeviceConnectionState::Offline => "offline",
        }
        .to_owned(),
        short_fingerprint: encode_base64url(&digest[..6]),
        paired_at_ms: record.paired_at,
        last_seen_at_ms: record.device.last_seen_at,
    }
}

fn normalize_device_display_name(value: &str) -> Result<String, PairingError> {
    let normalized = value.trim();
    if normalized.is_empty()
        || normalized.chars().count() > 32
        || normalized.chars().any(char::is_control)
    {
        return Err(PairingError::InvalidDisplayName);
    }
    Ok(normalized.to_owned())
}

pub fn resolve_active_sync_space(
    connection: &Connection,
    updated_at: u64,
) -> Result<Option<Uuid>, PairingError> {
    let settings = SettingsRepository::new(connection);
    if let Some(value) = settings
        .get(ACTIVE_SYNC_SPACE_ID_KEY)
        .map_err(|error| PairingError::Database(error.to_string()))?
    {
        if let Ok(space_id) = Uuid::parse_str(&value) {
            if is_selectable_space(connection, space_id)? {
                return Ok(Some(space_id));
            }
        }
    }

    let candidates = selectable_space_ids(connection)?;
    if candidates.len() != 1 {
        return Ok(None);
    }
    let space_id = candidates[0];
    settings
        .set(ACTIVE_SYNC_SPACE_ID_KEY, &space_id.to_string(), updated_at)
        .map_err(|error| PairingError::Database(error.to_string()))?;
    Ok(Some(space_id))
}

pub fn select_active_sync_space_in_database(
    connection: &Connection,
    space_id: &str,
    updated_at: u64,
) -> Result<SyncSpaceSummary, PairingError> {
    let space_id = Uuid::parse_str(space_id).map_err(|_| PairingError::InvalidSpaceId)?;
    if !is_selectable_space(connection, space_id)? {
        return Err(PairingError::MissingSpaceKeyRef);
    }
    SettingsRepository::new(connection)
        .set(ACTIVE_SYNC_SPACE_ID_KEY, &space_id.to_string(), updated_at)
        .map_err(|error| PairingError::Database(error.to_string()))?;
    list_sync_spaces(connection)?
        .into_iter()
        .find(|space| space.space_id == space_id.to_string())
        .ok_or(PairingError::MissingSpace)
}

pub fn run_space_hmac_diagnostic_in_database<S: SecretBytesStore>(
    connection: &Connection,
    secret_store: &S,
    updated_at: u64,
) -> Result<SpaceHmacDiagnosticSummary, PairingError> {
    let space_id =
        resolve_active_sync_space(connection, updated_at)?.ok_or(PairingError::MissingSpace)?;
    let space = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::MissingSpace)?;
    let mut space_key = load_space_key(connection, secret_store, space_id)?;
    let digest = content_hmac_digest(&space_key, SPACE_HMAC_DIAGNOSTIC_TEXT)
        .map_err(|error| PairingError::Serialize(error.to_string()));
    space_key.fill(0);
    let digest = digest?;
    let confirmation_code = hmac_confirmation_code(&digest)?;
    Ok(SpaceHmacDiagnosticSummary {
        space_id: space_id.to_string(),
        space_display_name: space.space.display_name,
        confirmation_code,
    })
}

pub fn hmac_confirmation_code(digest_base64url: &str) -> Result<String, PairingError> {
    let digest = decode_base64url(digest_base64url)
        .map_err(|error| PairingError::Serialize(error.to_string()))?;
    if digest.len() != 32 {
        return Err(PairingError::Serialize(
            "invalid HMAC-SHA-256 digest length".to_string(),
        ));
    }
    let prefix = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]);
    Ok(format!("{:06}", prefix % 1_000_000))
}

fn selectable_space_ids(connection: &Connection) -> Result<Vec<Uuid>, PairingError> {
    let records = SpaceRepository::new(connection)
        .list()
        .map_err(|error| PairingError::Database(error.to_string()))?;
    Ok(records
        .into_iter()
        .filter(|record| {
            record.space.state == SpaceState::Active && record.encrypted_space_key_ref.is_some()
        })
        .map(|record| record.space.space_id)
        .collect())
}

fn is_selectable_space(connection: &Connection, space_id: Uuid) -> Result<bool, PairingError> {
    let record = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?;
    Ok(record.is_some_and(|value| {
        value.space.state == SpaceState::Active && value.encrypted_space_key_ref.is_some()
    }))
}

pub fn expire_pairing_invitations(
    connection: &Connection,
    now_ms: u64,
) -> Result<usize, PairingError> {
    PairingInvitationRepository::new(connection)
        .expire_before(now_ms)
        .map_err(|error| PairingError::Database(error.to_string()))
}

pub fn create_pairing_invitation_for_space<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    space_id: &str,
    now_ms: u64,
) -> Result<PairingInvitationSummary, PairingError> {
    let space_id = Uuid::parse_str(space_id).map_err(|_| PairingError::InvalidSpaceId)?;
    let space = SpaceRepository::new(connection)
        .get(space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::MissingSpace)?;
    if space.encrypted_space_key_ref.is_none() {
        return Err(PairingError::MissingSpaceKeyRef);
    }
    PairingInvitationRepository::new(connection)
        .expire_before(now_ms)
        .map_err(|error| PairingError::Database(error.to_string()))?;
    let identity = ensure_local_device_identity(connection, secret_store, now_ms)
        .map_err(pairing_identity_error)?;
    let issuer_device_id = Uuid::parse_str(&identity.device_id)
        .map_err(|_| PairingError::Identity("local device id is not a UUID".to_string()))?;
    let invitation_id = Uuid::now_v7();
    let mut pairing_secret = random_pairing_secret()?;
    let pairing_secret_encoded = encode_base64url(&pairing_secret);
    let secret_verifier = pairing_secret_verifier(invitation_id, &pairing_secret);
    let expires_at_ms = now_ms.saturating_add(PAIRING_INVITATION_TTL_MS);
    let issuer_device_name = local_device_display_name();
    let payload = PairingInvitationPayload {
        app: "eggclip".to_string(),
        version: 1,
        kind: "pairingInvitation".to_string(),
        invitation_id: invitation_id.to_string(),
        space_id: space.space.space_id.to_string(),
        space_key_version: space.space.key_version,
        issuer_device_name: issuer_device_name.clone(),
        issuer_device_id: identity.device_id.clone(),
        issuer_identity_public_key: identity.identity_public_key.clone(),
        pairing_secret: pairing_secret_encoded,
        expires_at_ms,
        connection_hints: None,
    };
    let payload_json =
        serde_json::to_vec(&payload).map_err(|error| PairingError::Serialize(error.to_string()))?;
    let invitation = format!(
        "eggclip://pair?p={}",
        URL_SAFE_NO_PAD.encode(payload_json.as_slice())
    );
    let qr_svg = pairing_invitation_qr_svg(&invitation)?;
    let confirmation_code = confirmation_code(&payload_json);
    pairing_secret.fill(0);
    PairingInvitationRepository::new(connection)
        .insert(&PairingInvitationRecord {
            invitation_id,
            space_id: space.space.space_id,
            issuer_device_id,
            secret_verifier,
            state: PairingInvitationState::Active,
            created_at: now_ms,
            expires_at: expires_at_ms,
            consumed_at: None,
            consumed_by_device_id: None,
        })
        .map_err(|error| PairingError::Database(error.to_string()))?;

    Ok(PairingInvitationSummary {
        invitation_id: invitation_id.to_string(),
        space_id: space.space.space_id.to_string(),
        space_display_name: space.space.display_name,
        invitation,
        qr_svg,
        expires_at_ms,
        expires_in_seconds: PAIRING_INVITATION_TTL_MS / 1000,
        issuer_device_name,
        issuer_device_id: identity.device_id,
        issuer_short_fingerprint: identity.identity_public_key.chars().take(8).collect(),
        confirmation_code,
    })
}

pub fn consume_pairing_invitation(
    connection: &Connection,
    invitation_id: &str,
    pairing_secret: &str,
    consumer_device_id: &str,
    now_ms: u64,
) -> Result<(), PairingError> {
    let invitation_id =
        Uuid::parse_str(invitation_id).map_err(|_| PairingError::InvalidInvitation)?;
    let consumer_device_id =
        Uuid::parse_str(consumer_device_id).map_err(|_| PairingError::InvalidInvitation)?;
    let mut pairing_secret =
        decode_base64url(pairing_secret).map_err(|_| PairingError::InvalidInvitationSecret)?;
    if pairing_secret.len() != PAIRING_SECRET_BYTES {
        return Err(PairingError::InvalidInvitationSecret);
    }
    let mut secret = [0u8; PAIRING_SECRET_BYTES];
    secret.copy_from_slice(&pairing_secret);
    pairing_secret.fill(0);
    let verifier = pairing_secret_verifier(invitation_id, &secret);
    secret.fill(0);

    let repository = PairingInvitationRepository::new(connection);
    let record = repository
        .get(invitation_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::InvitationMissing)?;
    match record.state {
        PairingInvitationState::Consumed => return Err(PairingError::InvitationConsumed),
        PairingInvitationState::Expired => return Err(PairingError::InvitationExpired),
        PairingInvitationState::Active => {}
    }
    if record.expires_at <= now_ms {
        repository
            .expire_before(now_ms)
            .map_err(|error| PairingError::Database(error.to_string()))?;
        return Err(PairingError::InvitationExpired);
    }
    if !constant_time_eq(verifier.as_bytes(), record.secret_verifier.as_bytes()) {
        return Err(PairingError::InvalidInvitationSecret);
    }
    if !repository
        .mark_consumed(invitation_id, consumer_device_id, now_ms)
        .map_err(|error| PairingError::Database(error.to_string()))?
    {
        return Err(PairingError::InvitationConsumed);
    }
    Ok(())
}

pub fn accept_pairing_client_hello<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    client_hello_frame: &str,
    server_ephemeral_public_key: &str,
    server_hello_message_id: &str,
    now_ms: u64,
) -> Result<PairingServerHelloDraft, PairingError> {
    let ProtocolEnvelope::PreAuth(envelope) =
        parse_envelope(client_hello_frame).map_err(|_| PairingError::InvalidClientHello)?
    else {
        return Err(PairingError::InvalidClientHello);
    };
    if envelope.message_type != MessageType::ClientHello {
        return Err(PairingError::InvalidClientHello);
    }
    let client_hello: HelloPayload =
        serde_json::from_value(envelope.payload).map_err(|_| PairingError::InvalidClientHello)?;
    client_hello
        .validate()
        .map_err(|_| PairingError::InvalidClientHello)?;
    let pairing_context = client_hello
        .pairing_context
        .clone()
        .ok_or(PairingError::InvalidClientHello)?;
    let invitation_id = parse_pairing_invitation_context(&pairing_context)?;
    let invitation = PairingInvitationRepository::new(connection)
        .get(invitation_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::InvitationMissing)?;

    match invitation.state {
        PairingInvitationState::Consumed => return Err(PairingError::InvitationConsumed),
        PairingInvitationState::Expired => return Err(PairingError::InvitationExpired),
        PairingInvitationState::Active => {}
    }
    if invitation.expires_at <= now_ms {
        PairingInvitationRepository::new(connection)
            .expire_before(now_ms)
            .map_err(|error| PairingError::Database(error.to_string()))?;
        return Err(PairingError::InvitationExpired);
    }
    let client_space_id =
        Uuid::parse_str(&client_hello.space_id).map_err(|_| PairingError::InvalidClientHello)?;
    if client_space_id != invitation.space_id {
        return Err(PairingError::InvalidClientHello);
    }

    let local_identity = ensure_local_device_identity(connection, secret_store, now_ms)
        .map_err(pairing_identity_error)?;
    if local_identity.device_id != invitation.issuer_device_id.to_string() {
        return Err(PairingError::InvalidClientHello);
    }

    let server_hello = HelloPayload {
        space_id: client_hello.space_id.clone(),
        device_id: local_identity.device_id,
        identity_public_key: local_identity.identity_public_key,
        ephemeral_public_key: server_ephemeral_public_key.to_string(),
        capabilities: vec![
            Capability::TextPlain,
            Capability::SyncHeads,
            Capability::ItemBatch,
            Capability::ItemLive,
        ],
        pairing_context: Some(pairing_context.clone()),
    };
    server_hello
        .validate()
        .map_err(|_| PairingError::InvalidClientHello)?;
    let server_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
        message_type: MessageType::ServerHello,
        message_id: server_hello_message_id.to_string(),
        session_counter: envelope.session_counter.saturating_add(1),
        payload: serde_json::to_value(&server_hello)
            .map_err(|error| PairingError::Serialize(error.to_string()))?,
    })
    .map_err(|error| PairingError::Serialize(error.to_string()))?;

    Ok(PairingServerHelloDraft {
        invitation_id: invitation_id.to_string(),
        space_id: client_hello.space_id,
        peer_device_id: client_hello.device_id,
        peer_identity_public_key: client_hello.identity_public_key,
        peer_ephemeral_public_key: client_hello.ephemeral_public_key,
        server_device_id: server_hello.device_id,
        server_identity_public_key: server_hello.identity_public_key,
        server_ephemeral_public_key: server_ephemeral_public_key.to_string(),
        pairing_context,
        server_hello_frame,
    })
}

/// Accepts an authenticated-session bootstrap from a device that was paired earlier.
///
/// This deliberately has a separate context from invitation pairing.  It proves possession
/// of the saved device identity key, but it must never consume an invitation or deliver a
/// space key again.
pub fn accept_trusted_device_client_hello<S: SecretBytesStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    client_hello_frame: &str,
    server_ephemeral_public_key: &str,
    server_hello_message_id: &str,
    now_ms: u64,
) -> Result<PairingServerHelloDraft, PairingError> {
    let ProtocolEnvelope::PreAuth(envelope) =
        parse_envelope(client_hello_frame).map_err(|_| PairingError::InvalidClientHello)?
    else {
        return Err(PairingError::InvalidClientHello);
    };
    if envelope.message_type != MessageType::ClientHello {
        return Err(PairingError::InvalidClientHello);
    }
    let client_hello: HelloPayload =
        serde_json::from_value(envelope.payload).map_err(|_| PairingError::InvalidClientHello)?;
    client_hello
        .validate()
        .map_err(|_| PairingError::InvalidClientHello)?;
    let pairing_context = client_hello
        .pairing_context
        .clone()
        .ok_or(PairingError::InvalidClientHello)?;
    let context_space_id = parse_trusted_device_context(&pairing_context)?;
    let client_space_id =
        Uuid::parse_str(&client_hello.space_id).map_err(|_| PairingError::InvalidClientHello)?;
    let client_device_id =
        Uuid::parse_str(&client_hello.device_id).map_err(|_| PairingError::InvalidClientHello)?;
    if context_space_id != client_space_id {
        return Err(PairingError::InvalidClientHello);
    }

    let space = SpaceRepository::new(connection)
        .get(context_space_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::MissingSpace)?;
    if space.space.state != SpaceState::Active {
        return Err(PairingError::InvalidClientHello);
    }
    let device = DeviceRepository::new(connection)
        .get(client_device_id)
        .map_err(|error| PairingError::Database(error.to_string()))?
        .ok_or(PairingError::InvalidClientHello)?;
    if device.device.space_id != context_space_id
        || device.device.trust_state != DeviceTrustState::Trusted
        || device.revoked_at.is_some()
        || device.device.identity_public_key_ref != client_hello.identity_public_key
    {
        return Err(PairingError::InvalidClientHello);
    }

    let local_identity = ensure_local_device_identity(connection, secret_store, now_ms)
        .map_err(pairing_identity_error)?;
    let server_hello = HelloPayload {
        space_id: client_hello.space_id.clone(),
        device_id: local_identity.device_id,
        identity_public_key: local_identity.identity_public_key,
        ephemeral_public_key: server_ephemeral_public_key.to_string(),
        capabilities: vec![
            Capability::TextPlain,
            Capability::SyncHeads,
            Capability::ItemBatch,
            Capability::ItemLive,
        ],
        pairing_context: Some(pairing_context.clone()),
    };
    server_hello
        .validate()
        .map_err(|_| PairingError::InvalidClientHello)?;
    let server_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
        message_type: MessageType::ServerHello,
        message_id: server_hello_message_id.to_string(),
        session_counter: envelope.session_counter.saturating_add(1),
        payload: serde_json::to_value(&server_hello)
            .map_err(|error| PairingError::Serialize(error.to_string()))?,
    })
    .map_err(|error| PairingError::Serialize(error.to_string()))?;

    Ok(PairingServerHelloDraft {
        // The generic auth-proof draft predates trusted reconnect.  This field is not used
        // by trusted reconnect; the transport identifies that path from pairing_context.
        invitation_id: client_hello.device_id.clone(),
        space_id: client_hello.space_id,
        peer_device_id: client_hello.device_id,
        peer_identity_public_key: client_hello.identity_public_key,
        peer_ephemeral_public_key: client_hello.ephemeral_public_key,
        server_device_id: server_hello.device_id,
        server_identity_public_key: server_hello.identity_public_key,
        server_ephemeral_public_key: server_ephemeral_public_key.to_string(),
        pairing_context,
        server_hello_frame,
    })
}

pub fn accept_pairing_auth_proof(
    handshake: PairingServerAuthProofInput,
    auth_proof_frame: &str,
    auth_ok_message_id: &str,
) -> Result<PairingServerAuthProofAccepted, PairingError> {
    let ProtocolEnvelope::PreAuth(envelope) =
        parse_envelope(auth_proof_frame).map_err(|_| PairingError::InvalidAuthProof)?
    else {
        return Err(PairingError::InvalidAuthProof);
    };
    if envelope.message_type != MessageType::AuthProof {
        return Err(PairingError::InvalidAuthProof);
    }
    let proof: AuthProofPayload =
        serde_json::from_value(envelope.payload).map_err(|_| PairingError::InvalidAuthProof)?;
    proof
        .validate()
        .map_err(|_| PairingError::InvalidAuthProof)?;
    if proof.role != AuthRole::Client || proof.signature_algorithm != SignatureAlgorithm::Ed25519 {
        return Err(PairingError::InvalidAuthProof);
    }

    let transcript_input = AuthTranscriptInput {
        role: AuthRole::Client,
        space_id: handshake.space_id.clone(),
        local_device_id: handshake.peer_device_id.clone(),
        remote_device_id: handshake.server_device_id.clone(),
        local_identity_public_key: handshake.peer_identity_public_key.clone(),
        remote_identity_public_key: handshake.server_identity_public_key.clone(),
        local_ephemeral_public_key: handshake.peer_ephemeral_public_key.clone(),
        remote_ephemeral_public_key: handshake.server_ephemeral_public_key.clone(),
        pairing_context: handshake.pairing_context.clone(),
    };
    let canonical_transcript =
        canonical_auth_transcript(&transcript_input).map_err(|_| PairingError::InvalidAuthProof)?;
    let transcript_hash = auth_transcript_hash_base64url(&transcript_input)
        .map_err(|_| PairingError::InvalidAuthProof)?;
    if proof.transcript_hash != transcript_hash {
        return Err(PairingError::InvalidAuthProof);
    }

    let peer_identity_public_key = fixed_bytes::<ED25519_PUBLIC_KEY_BYTES>(
        &decode_base64url(&handshake.peer_identity_public_key)
            .map_err(|_| PairingError::InvalidAuthProof)?,
        "peerIdentityPublicKey",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    let signature = fixed_bytes::<ED25519_SIGNATURE_BYTES>(
        &decode_base64url(&proof.signature).map_err(|_| PairingError::InvalidAuthProof)?,
        "signature",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    verify_ed25519_signature(
        peer_identity_public_key,
        canonical_transcript.as_bytes(),
        signature,
    )
    .map_err(|_| PairingError::AuthProofSignatureFailed)?;

    let peer_ephemeral_public_key = fixed_bytes::<X25519_PUBLIC_KEY_BYTES>(
        &decode_base64url(&handshake.peer_ephemeral_public_key)
            .map_err(|_| PairingError::InvalidAuthProof)?,
        "peerEphemeralPublicKey",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    let shared_secret = handshake
        .server_ephemeral_secret
        .shared_secret(peer_ephemeral_public_key);
    let transcript_salt = fixed_bytes::<32>(
        &decode_base64url(&transcript_hash).map_err(|_| PairingError::InvalidAuthProof)?,
        "transcriptHash",
    )
    .map_err(|_| PairingError::InvalidAuthProof)?;
    let session_keys = derive_session_keys(shared_secret, &transcript_salt)
        .map_err(|_| PairingError::SessionKeyDerivationFailed)?;
    let auth_ok_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
        message_type: MessageType::AuthOk,
        message_id: auth_ok_message_id.to_string(),
        session_counter: envelope.session_counter.saturating_add(1),
        payload: serde_json::json!({}),
    })
    .map_err(|error| PairingError::Serialize(error.to_string()))?;

    Ok(PairingServerAuthProofAccepted {
        invitation_id: handshake.invitation_id,
        space_id: handshake.space_id,
        peer_device_id: handshake.peer_device_id,
        peer_identity_public_key: handshake.peer_identity_public_key,
        transcript_hash,
        transcript_salt,
        shared_secret,
        session_keys,
        auth_ok_frame,
    })
}

fn normalize_space_display_name(display_name: &str) -> Result<String, PairingError> {
    let normalized = display_name.trim();
    if normalized.is_empty() || normalized.chars().count() > 64 {
        return Err(PairingError::InvalidDisplayName);
    }
    Ok(normalized.to_string())
}

fn parse_pairing_invitation_context(value: &str) -> Result<Uuid, PairingError> {
    let invitation_id = value
        .strip_prefix("pairing-invitation:v1:")
        .ok_or(PairingError::InvalidClientHello)?;
    Uuid::parse_str(invitation_id).map_err(|_| PairingError::InvalidClientHello)
}

fn parse_trusted_device_context(value: &str) -> Result<Uuid, PairingError> {
    let space_id = value
        .strip_prefix("trusted-device:")
        .ok_or(PairingError::InvalidClientHello)?;
    Uuid::parse_str(space_id).map_err(|_| PairingError::InvalidClientHello)
}

fn random_space_key() -> Result<[u8; SPACE_KEY_BYTES], PairingError> {
    let mut key = [0u8; SPACE_KEY_BYTES];
    getrandom::getrandom(&mut key).map_err(|_| PairingError::RandomUnavailable)?;
    Ok(key)
}

fn random_pairing_secret() -> Result<[u8; PAIRING_SECRET_BYTES], PairingError> {
    let mut secret = [0u8; PAIRING_SECRET_BYTES];
    getrandom::getrandom(&mut secret).map_err(|_| PairingError::RandomUnavailable)?;
    Ok(secret)
}

fn space_key_ref(space_id: Uuid, key_version: u32) -> String {
    format!("credential://eggclip/space-key/{space_id}/v{key_version}")
}

fn local_device_display_name() -> String {
    let raw = std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "Windows 桌面".to_string());
    let normalized: String = raw
        .trim()
        .chars()
        .filter(|character| !character.is_control())
        .take(32)
        .collect();
    if normalized.is_empty() {
        "Windows 桌面".to_string()
    } else {
        normalized
    }
}

fn pairing_secret_store_error(error: SecretStoreError) -> PairingError {
    PairingError::KeyStore(error.to_string())
}

fn pairing_identity_error(error: IdentityError) -> PairingError {
    match error {
        IdentityError::Database(message) => PairingError::Database(message),
        IdentityError::KeyStore(message) => PairingError::KeyStore(message),
        IdentityError::RandomUnavailable => PairingError::RandomUnavailable,
        other => PairingError::Identity(other.to_string()),
    }
}

fn confirmation_code(payload_json: &[u8]) -> String {
    let digest = Sha256::digest(payload_json);
    let value = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]) % 1_000_000;
    format!("{value:06}")
}

fn pairing_secret_verifier(
    invitation_id: Uuid,
    pairing_secret: &[u8; PAIRING_SECRET_BYTES],
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"EggClip pairing invitation verifier v1\0");
    hasher.update(invitation_id.as_bytes());
    hasher.update(pairing_secret);
    URL_SAFE_NO_PAD.encode(hasher.finalize())
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut diff = 0u8;
    for (left, right) in left.iter().zip(right.iter()) {
        diff |= left ^ right;
    }
    diff == 0
}

fn validate_pairing_invitation_uri(invitation: &str) -> Result<(), PairingError> {
    let payload = invitation
        .strip_prefix("eggclip://pair?p=")
        .ok_or(PairingError::InvalidInvitation)?;
    let payload_json = URL_SAFE_NO_PAD
        .decode(payload)
        .map_err(|_| PairingError::InvalidInvitation)?;
    let decoded: PairingInvitationPayload =
        serde_json::from_slice(&payload_json).map_err(|_| PairingError::InvalidInvitation)?;
    if decoded.app != "eggclip"
        || decoded.version != 1
        || decoded.kind != "pairingInvitation"
        || Uuid::parse_str(&decoded.invitation_id).is_err()
        || Uuid::parse_str(&decoded.space_id).is_err()
        || decoded.issuer_device_name.trim().is_empty()
        || decoded.issuer_device_name.chars().count() > 32
        || Uuid::parse_str(&decoded.issuer_device_id).is_err()
        || decode_base64url(&decoded.pairing_secret)
            .map(|secret| secret.len() != PAIRING_SECRET_BYTES)
            .unwrap_or(true)
    {
        return Err(PairingError::InvalidInvitation);
    }
    if let Some(hints) = &decoded.connection_hints {
        if hints.transport != "ws" || hints.endpoints.is_empty() || hints.endpoints.len() > 5 {
            return Err(PairingError::InvalidInvitation);
        }
        for endpoint in &hints.endpoints {
            let address = endpoint
                .host
                .parse::<std::net::Ipv4Addr>()
                .map_err(|_| PairingError::InvalidInvitation)?;
            if endpoint.port == 0
                || address.is_unspecified()
                || address.is_loopback()
                || address.is_multicast()
            {
                return Err(PairingError::InvalidInvitation);
            }
        }
    }
    Ok(())
}

fn pairing_invitation_qr_svg(invitation: &str) -> Result<String, PairingError> {
    let code = QrCode::with_error_correction_level(invitation.as_bytes(), EcLevel::M)
        .map_err(|error| PairingError::QrCode(error.to_string()))?;
    Ok(code
        .render::<svg::Color>()
        .min_dimensions(
            PAIRING_INVITATION_QR_MIN_DIMENSIONS,
            PAIRING_INVITATION_QR_MIN_DIMENSIONS,
        )
        .dark_color(svg::Color("#2f2300"))
        .light_color(svg::Color("#fff8e7"))
        .build())
}

#[cfg(test)]
#[derive(Default)]
struct MemorySecretStore {
    secrets: HashMap<String, Vec<u8>>,
}

#[cfg(test)]
impl SecretBytesStore for MemorySecretStore {
    fn load_secret(&self, secret_ref: &str) -> Result<Option<Vec<u8>>, SecretStoreError> {
        Ok(self.secrets.get(secret_ref).cloned())
    }

    fn save_secret(&mut self, secret_ref: &str, secret: &[u8]) -> Result<(), SecretStoreError> {
        self.secrets.insert(secret_ref.to_string(), secret.to_vec());
        Ok(())
    }

    fn delete_secret(&mut self, secret_ref: &str) -> Result<(), SecretStoreError> {
        self.secrets.remove(secret_ref);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{open_in_memory_database, repositories::SpaceRepository};

    fn decode_invitation_payload(invitation: &str) -> PairingInvitationPayload {
        let payload = invitation
            .strip_prefix("eggclip://pair?p=")
            .expect("invitation should use eggclip pair scheme");
        let json = URL_SAFE_NO_PAD
            .decode(payload)
            .expect("payload should be base64url");
        serde_json::from_slice(&json).expect("payload should decode")
    }

    #[test]
    fn creates_space_key_in_external_secret_store_and_only_ref_in_sqlite() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();

        let space = create_sync_space(&mut connection, &mut store, " 默认空间 ", 1_700_000_000_000)
            .expect("space should be created");

        assert_eq!(space.display_name, "默认空间");
        assert_eq!(space.key_version, INITIAL_SPACE_KEY_VERSION);
        assert!(space
            .space_key_ref
            .starts_with("credential://eggclip/space-key/"));
        assert_eq!(
            store
                .load_secret(&space.space_key_ref)
                .expect("secret store should load")
                .expect("space key should exist")
                .len(),
            SPACE_KEY_BYTES
        );

        let record = SpaceRepository::new(&connection)
            .get(Uuid::parse_str(&space.space_id).expect("space id should parse"))
            .expect("space should query")
            .expect("space should exist");
        assert_eq!(record.encrypted_space_key_ref, Some(space.space_key_ref));
        assert_eq!(record.space.display_name, "默认空间");
    }

    #[test]
    fn load_space_key_returns_secret_from_external_store() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let key = load_space_key(
            &connection,
            &store,
            Uuid::parse_str(&space.space_id).expect("space id should parse"),
        )
        .expect("space key should load");

        assert_eq!(key.len(), SPACE_KEY_BYTES);
        assert_eq!(
            key.to_vec(),
            store
                .load_secret(&space.space_key_ref)
                .expect("secret should load")
                .expect("secret should exist")
        );
    }

    #[test]
    fn lists_spaces_without_loading_raw_space_keys() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let first = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("first space should be created");
        let second = create_sync_space(&mut connection, &mut store, "临时空间", 1_700_000_000_100)
            .expect("second space should be created");

        let spaces = list_sync_spaces(&connection).expect("spaces should list");

        assert_eq!(spaces.len(), 2);
        assert_eq!(spaces[0].space_id, second.space_id);
        assert_eq!(spaces[1].space_id, first.space_id);
        assert!(spaces
            .iter()
            .all(|space| space.space_key_ref.starts_with("credential://")));
    }

    #[test]
    fn auto_selects_only_space_and_requires_choice_when_multiple_exist() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let first = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("first space should be created");

        assert_eq!(
            resolve_active_sync_space(&connection, 1_700_000_000_100)
                .expect("single space should resolve")
                .map(|value| value.to_string()),
            Some(first.space_id.clone())
        );

        let second = create_sync_space(&mut connection, &mut store, "第二空间", 1_700_000_000_200)
            .expect("second space should be created");
        SettingsRepository::new(&connection)
            .set(ACTIVE_SYNC_SPACE_ID_KEY, "invalid", 1_700_000_000_300)
            .expect("invalid selection fixture should save");
        assert_eq!(
            resolve_active_sync_space(&connection, 1_700_000_000_400)
                .expect("ambiguous spaces should not guess"),
            None
        );

        let selected =
            select_active_sync_space_in_database(&connection, &second.space_id, 1_700_000_000_500)
                .expect("explicit selection should save");
        assert_eq!(selected.space_id, second.space_id);
        assert_eq!(
            resolve_active_sync_space(&connection, 1_700_000_000_600)
                .expect("saved selection should resolve")
                .map(|value| value.to_string()),
            Some(selected.space_id)
        );
    }

    #[test]
    fn space_hmac_diagnostic_matches_shared_confirmation_vector() {
        let vector: serde_json::Value = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../protocol/test-vectors/crypto/hmac-sha256.valid.json"
        )))
        .expect("HMAC vector should parse");
        let key = decode_base64url(vector["key"].as_str().expect("vector key should exist"))
            .expect("vector key should decode");
        let expected_code = vector["confirmationCode"]
            .as_str()
            .expect("confirmation code should exist");
        assert_eq!(
            hmac_confirmation_code(
                vector["digest"]
                    .as_str()
                    .expect("vector digest should exist")
            )
            .expect("digest code should derive"),
            expected_code
        );

        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(
            &mut connection,
            &mut store,
            "跨端诊断空间",
            1_700_000_000_000,
        )
        .expect("space should be created");
        store
            .save_secret(&space.space_key_ref, &key)
            .expect("vector key should replace random test key");

        let diagnostic =
            run_space_hmac_diagnostic_in_database(&connection, &store, 1_700_000_000_100)
                .expect("diagnostic should run");
        assert_eq!(diagnostic.space_id, space.space_id);
        assert_eq!(diagnostic.confirmation_code, expected_code);
    }

    #[test]
    fn ensures_default_sync_space_once_and_reuses_existing_space() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();

        let first =
            ensure_default_sync_space_in_database(&mut connection, &mut store, 1_700_000_000_000)
                .expect("default space should be created");
        let second =
            ensure_default_sync_space_in_database(&mut connection, &mut store, 1_700_000_000_500)
                .expect("existing default space should be reused");
        let spaces = list_sync_spaces(&connection).expect("spaces should list");

        assert_eq!(first.display_name, DEFAULT_SPACE_DISPLAY_NAME);
        assert_eq!(second.space_id, first.space_id);
        assert_eq!(second.created_at_ms, first.created_at_ms);
        assert_eq!(spaces.len(), 1);
        assert_eq!(store.secrets.len(), 1);
    }

    #[test]
    fn ignores_internal_history_space_when_ensuring_default_sync_space() {
        let mut connection = open_in_memory_database().expect("database should open");
        connection
            .execute(
                "INSERT INTO spaces(
                   space_id, display_name, encrypted_space_key_ref, key_version,
                   state, created_at, updated_at
                 ) VALUES (?1, '本机历史', NULL, 1, 'active', ?2, ?2)",
                rusqlite::params![
                    "018ff6ef-c394-7d08-8b99-4b7d10f2767a",
                    1_700_000_000_000_i64
                ],
            )
            .expect("internal history space should insert");
        let mut store = MemorySecretStore::default();

        let default =
            ensure_default_sync_space_in_database(&mut connection, &mut store, 1_700_000_000_500)
                .expect("keyed default space should be created");
        let spaces = list_sync_spaces(&connection).expect("selectable spaces should list");

        assert_eq!(default.display_name, DEFAULT_SPACE_DISPLAY_NAME);
        assert_eq!(spaces.len(), 1);
        assert_eq!(spaces[0].space_id, default.space_id);
        assert_eq!(store.secrets.len(), 1);
    }

    #[test]
    fn deletes_unused_sync_space_and_keeps_another_space_active() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let first = create_sync_space(&mut connection, &mut store, "空间 A", 1_700_000_000_000)
            .expect("first space should create");
        let second = create_sync_space(&mut connection, &mut store, "空间 B", 1_700_000_000_100)
            .expect("second space should create");
        SettingsRepository::new(&connection)
            .set(ACTIVE_SYNC_SPACE_ID_KEY, &first.space_id, 1_700_000_000_200)
            .expect("active space should save");

        let deleted = delete_sync_space_in_database(
            &mut connection,
            &mut store,
            Uuid::parse_str(&first.space_id).expect("space id should parse"),
            1_700_000_000_300,
        )
        .expect("unused space should delete");

        assert_eq!(deleted.deleted_space_id, first.space_id);
        assert_eq!(deleted.active_space_id, second.space_id);
        assert!(deleted.credential_deleted);
        assert_eq!(list_sync_spaces(&connection).unwrap().len(), 1);
        assert!(!store.secrets.contains_key(&first.space_key_ref));
        assert!(store.secrets.contains_key(&second.space_key_ref));
    }

    #[test]
    fn creates_pairing_invitation_with_high_entropy_secret_and_expiry() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);

        assert_eq!(invitation.space_id, space.space_id);
        assert_eq!(invitation.space_display_name, "默认空间");
        assert_eq!(invitation.expires_at_ms, 1_700_000_300_500);
        assert_eq!(invitation.expires_in_seconds, 300);
        assert_eq!(payload.app, "eggclip");
        assert_eq!(payload.version, 1);
        assert_eq!(payload.kind, "pairingInvitation");
        assert_eq!(payload.invitation_id, invitation.invitation_id);
        Uuid::parse_str(&invitation.invitation_id).expect("invitation id should be a UUID");
        assert_eq!(payload.space_id, space.space_id);
        assert_eq!(payload.space_key_version, INITIAL_SPACE_KEY_VERSION);
        assert!(!invitation.issuer_device_name.trim().is_empty());
        assert_eq!(payload.issuer_device_name, invitation.issuer_device_name);
        assert_eq!(
            decode_base64url_pairing_secret(&payload.pairing_secret).len(),
            PAIRING_SECRET_BYTES
        );
        assert_eq!(payload.expires_at_ms, invitation.expires_at_ms);
        assert_eq!(payload.issuer_device_id, invitation.issuer_device_id);
        assert!(payload.issuer_identity_public_key.len() >= 43);
        assert_eq!(invitation.confirmation_code.len(), 6);
        assert!(invitation.qr_svg.contains("<svg"));
        assert!(!invitation.qr_svg.contains(&payload.pairing_secret));

        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&invitation.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should be registered");
        assert_eq!(stored.state, PairingInvitationState::Active);
        assert_eq!(stored.space_id.to_string(), space.space_id);
        assert_eq!(stored.expires_at, invitation.expires_at_ms);
        assert_ne!(stored.secret_verifier, payload.pairing_secret);
    }

    #[test]
    fn pairing_invitation_secrets_are_not_constant() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let first = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("first invitation should be created");
        let second = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_600,
        )
        .expect("second invitation should be created");

        assert_ne!(
            decode_invitation_payload(&first.invitation).pairing_secret,
            decode_invitation_payload(&second.invitation).pairing_secret
        );
    }

    #[test]
    fn creating_invitation_expires_previous_active_invitations() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");

        let first = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("first invitation should be created");
        let second = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            first.expires_at_ms,
        )
        .expect("second invitation should be created");
        let invitations = PairingInvitationRepository::new(&connection);
        let first_record = invitations
            .get(Uuid::parse_str(&first.invitation_id).expect("first id should parse"))
            .expect("first invitation should query")
            .expect("first invitation should exist");
        let second_record = invitations
            .get(Uuid::parse_str(&second.invitation_id).expect("second id should parse"))
            .expect("second invitation should query")
            .expect("second invitation should exist");

        assert_eq!(first_record.state, PairingInvitationState::Expired);
        assert_eq!(second_record.state, PairingInvitationState::Active);
    }

    #[test]
    fn expiry_sweep_marks_only_elapsed_active_invitations() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");

        assert_eq!(
            expire_pairing_invitations(&connection, invitation.expires_at_ms - 1)
                .expect("sweep before expiry should run"),
            0
        );
        assert_eq!(
            expire_pairing_invitations(&connection, invitation.expires_at_ms)
                .expect("sweep at expiry should run"),
            1
        );
        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&invitation.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should exist");

        assert_eq!(stored.state, PairingInvitationState::Expired);
    }

    #[test]
    fn validates_pairing_invitation_uri_before_copy() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");

        validate_pairing_invitation_uri(&invitation.invitation)
            .expect("generated invitation should validate");
        assert_eq!(
            validate_pairing_invitation_uri("https://example.com/not-eggclip"),
            Err(PairingError::InvalidInvitation)
        );
        assert_eq!(
            validate_pairing_invitation_uri("eggclip://pair?p=not-base64url"),
            Err(PairingError::InvalidInvitation)
        );
    }

    #[test]
    fn consumes_pairing_invitation_once_with_matching_secret() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let consumer_device_id = Uuid::now_v7().to_string();

        consume_pairing_invitation(
            &connection,
            &payload.invitation_id,
            &payload.pairing_secret,
            &consumer_device_id,
            1_700_000_001_000,
        )
        .expect("invitation should consume");
        assert_eq!(
            consume_pairing_invitation(
                &connection,
                &payload.invitation_id,
                &payload.pairing_secret,
                &consumer_device_id,
                1_700_000_001_001,
            ),
            Err(PairingError::InvitationConsumed)
        );

        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&payload.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should exist");
        assert_eq!(stored.state, PairingInvitationState::Consumed);
        assert_eq!(
            stored
                .consumed_by_device_id
                .map(|device_id| device_id.to_string()),
            Some(consumer_device_id)
        );
    }

    #[test]
    fn accepts_pairing_client_hello_and_builds_server_hello_without_consuming_invitation() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let client_hello = HelloPayload {
            space_id: payload.space_id.clone(),
            device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            identity_public_key: encode_base64url(&[1u8; 32]),
            ephemeral_public_key: encode_base64url(&[2u8; 32]),
            capabilities: vec![Capability::TextPlain, Capability::SyncHeads],
            pairing_context: Some(format!("pairing-invitation:v1:{}", payload.invitation_id)),
        };
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000001".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&client_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");

        let result = accept_pairing_client_hello(
            &mut connection,
            &mut store,
            &client_hello_frame,
            &encode_base64url(&[3u8; 32]),
            "018ff6f1-0000-7000-8000-000000000002",
            1_700_000_001_000,
        )
        .expect("client hello should be accepted");

        assert_eq!(result.invitation_id, payload.invitation_id);
        assert_eq!(result.peer_device_id, client_hello.device_id);
        assert_eq!(
            result.peer_identity_public_key,
            client_hello.identity_public_key
        );
        assert_eq!(
            result.pairing_context,
            format!("pairing-invitation:v1:{}", payload.invitation_id)
        );
        let ProtocolEnvelope::PreAuth(server_hello_envelope) =
            parse_envelope(&result.server_hello_frame).expect("server hello should parse")
        else {
            panic!("server hello should be pre-auth");
        };
        assert_eq!(server_hello_envelope.message_type, MessageType::ServerHello);
        assert_eq!(server_hello_envelope.session_counter, 1);
        let server_hello: HelloPayload = serde_json::from_value(server_hello_envelope.payload)
            .expect("server hello payload should parse");
        assert_eq!(server_hello.space_id, payload.space_id);
        assert_eq!(server_hello.device_id, payload.issuer_device_id);
        assert_eq!(
            server_hello.pairing_context.as_deref(),
            Some(result.pairing_context.as_str())
        );
        let stored = PairingInvitationRepository::new(&connection)
            .get(Uuid::parse_str(&payload.invitation_id).expect("invitation id should parse"))
            .expect("invitation should query")
            .expect("invitation should exist");
        assert_eq!(stored.state, PairingInvitationState::Active);
    }

    #[test]
    fn accepts_trusted_device_client_hello_only_when_saved_identity_matches() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let peer_device_id =
            Uuid::parse_str("018ff6f0-4adf-7d31-a987-3ef2b25d0212").expect("peer id should parse");
        let client_identity = crate::crypto::Ed25519Identity::from_seed([9u8; 32]);
        let client_x25519 = X25519Secret::from_private_key([8u8; 32]);
        let server_x25519 = X25519Secret::from_private_key([7u8; 32]);
        let client_identity_public_key = encode_base64url(&client_identity.public_key());
        DeviceRepository::new(&connection)
            .upsert(&crate::storage::repositories::DeviceRecord {
                device: crate::sync::Device {
                    device_id: peer_device_id,
                    space_id: Uuid::parse_str(&space.space_id).expect("space id should parse"),
                    display_name: "HarmonyOS 设备".to_string(),
                    identity_public_key_ref: client_identity_public_key.clone(),
                    trust_state: DeviceTrustState::Trusted,
                    connection_state: crate::sync::DeviceConnectionState::Offline,
                    last_seen_at: None,
                },
                paired_at: Some(1_700_000_000_000),
                revoked_at: None,
            })
            .expect("trusted device should persist");
        let client_hello = HelloPayload {
            space_id: space.space_id.clone(),
            device_id: peer_device_id.to_string(),
            identity_public_key: client_identity_public_key,
            ephemeral_public_key: encode_base64url(&client_x25519.public_key()),
            capabilities: vec![Capability::TextPlain, Capability::SyncHeads],
            pairing_context: Some(format!("trusted-device:{}", space.space_id)),
        };
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000001".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&client_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");

        let server_hello = accept_trusted_device_client_hello(
            &mut connection,
            &mut store,
            &client_hello_frame,
            &encode_base64url(&server_x25519.public_key()),
            "018ff6f1-0000-7000-8000-000000000002",
            1_700_000_001_000,
        )
        .expect("saved trusted device should be accepted");
        assert_eq!(
            server_hello.pairing_context,
            format!("trusted-device:{}", space.space_id)
        );

        let transcript_input = AuthTranscriptInput {
            role: AuthRole::Client,
            space_id: server_hello.space_id.clone(),
            local_device_id: server_hello.peer_device_id.clone(),
            remote_device_id: server_hello.server_device_id.clone(),
            local_identity_public_key: server_hello.peer_identity_public_key.clone(),
            remote_identity_public_key: server_hello.server_identity_public_key.clone(),
            local_ephemeral_public_key: server_hello.peer_ephemeral_public_key.clone(),
            remote_ephemeral_public_key: server_hello.server_ephemeral_public_key.clone(),
            pairing_context: server_hello.pairing_context.clone(),
        };
        let auth_proof = AuthProofPayload {
            role: AuthRole::Client,
            signature_algorithm: SignatureAlgorithm::Ed25519,
            transcript_hash: auth_transcript_hash_base64url(&transcript_input)
                .expect("hash should build"),
            signature: encode_base64url(
                &client_identity.sign(
                    canonical_auth_transcript(&transcript_input)
                        .expect("transcript should build")
                        .as_bytes(),
                ),
            ),
        };
        let auth_proof_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::AuthProof,
            message_id: "018ff6f1-0000-7000-8000-000000000003".to_string(),
            session_counter: 2,
            payload: serde_json::to_value(&auth_proof).expect("proof should serialize"),
        })
        .expect("proof should serialize");
        let accepted = accept_pairing_auth_proof(
            PairingServerAuthProofInput {
                invitation_id: server_hello.invitation_id,
                space_id: server_hello.space_id,
                peer_device_id: server_hello.peer_device_id,
                peer_identity_public_key: server_hello.peer_identity_public_key,
                peer_ephemeral_public_key: server_hello.peer_ephemeral_public_key,
                server_device_id: server_hello.server_device_id,
                server_identity_public_key: server_hello.server_identity_public_key,
                server_ephemeral_public_key: server_hello.server_ephemeral_public_key,
                pairing_context: server_hello.pairing_context,
                server_ephemeral_secret: server_x25519.clone(),
            },
            &auth_proof_frame,
            "018ff6f1-0000-7000-8000-000000000004",
        )
        .expect("trusted proof should be accepted");
        assert_eq!(
            accepted.shared_secret,
            client_x25519.shared_secret(server_x25519.public_key())
        );

        let wrong_identity_hello = HelloPayload {
            identity_public_key: encode_base64url(&[7u8; 32]),
            ..client_hello
        };
        let wrong_identity_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000005".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&wrong_identity_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");
        assert_eq!(
            accept_trusted_device_client_hello(
                &mut connection,
                &mut store,
                &wrong_identity_frame,
                &encode_base64url(&server_x25519.public_key()),
                "018ff6f1-0000-7000-8000-000000000006",
                1_700_000_001_000,
            ),
            Err(PairingError::InvalidClientHello)
        );
    }

    #[test]
    fn renames_revokes_and_rotates_key_for_trusted_device() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let space_id = Uuid::parse_str(&space.space_id).expect("space id should parse");
        let device_id = Uuid::parse_str("018ff6f0-4adf-7d31-a987-3ef2b25d0212")
            .expect("device id should parse");
        DeviceRepository::new(&connection)
            .upsert(&crate::storage::repositories::DeviceRecord {
                device: crate::sync::Device {
                    device_id,
                    space_id,
                    display_name: "HarmonyOS 设备".to_owned(),
                    identity_public_key_ref: encode_base64url(&[9u8; 32]),
                    trust_state: DeviceTrustState::Trusted,
                    connection_state: DeviceConnectionState::Online,
                    last_seen_at: Some(1_700_000_001_000),
                },
                paired_at: Some(1_700_000_000_500),
                revoked_at: None,
            })
            .expect("trusted device should persist");

        let renamed =
            rename_trusted_device_in_database(&connection, &device_id.to_string(), "  我的 Mate  ")
                .expect("trusted device should rename");
        assert_eq!(renamed.display_name, "我的 Mate");
        assert_eq!(renamed.connection_state, "online");
        assert_eq!(
            list_trusted_devices_in_database(&connection).unwrap().len(),
            1
        );

        let rotation = revoke_device_and_rotate_space_key(
            &mut connection,
            &mut store,
            device_id,
            1_700_000_002_000,
        )
        .expect("device removal should rotate key");
        assert_eq!(rotation.key_version, 2);
        assert_ne!(rotation.space_key, [0u8; SPACE_KEY_BYTES]);
        assert_eq!(
            SpaceRepository::new(&connection)
                .get(space_id)
                .unwrap()
                .unwrap()
                .space
                .key_version,
            2
        );
        let revoked = DeviceRepository::new(&connection)
            .get(device_id)
            .unwrap()
            .unwrap();
        assert_eq!(revoked.device.trust_state, DeviceTrustState::Revoked);
        assert_eq!(revoked.revoked_at, Some(1_700_000_002_000));
        assert!(list_trusted_devices_in_database(&connection)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn accepts_pairing_auth_proof_and_derives_server_session_material() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let client_identity_seed = [9u8; 32];
        let client_identity = crate::crypto::Ed25519Identity::from_seed(client_identity_seed);
        let client_x25519 = X25519Secret::from_private_key([8u8; 32]);
        let server_x25519 = X25519Secret::from_private_key([7u8; 32]);
        let client_hello = HelloPayload {
            space_id: payload.space_id.clone(),
            device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            identity_public_key: encode_base64url(&client_identity.public_key()),
            ephemeral_public_key: encode_base64url(&client_x25519.public_key()),
            capabilities: vec![Capability::TextPlain, Capability::SyncHeads],
            pairing_context: Some(format!("pairing-invitation:v1:{}", payload.invitation_id)),
        };
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000001".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&client_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");
        let server_hello = accept_pairing_client_hello(
            &mut connection,
            &mut store,
            &client_hello_frame,
            &encode_base64url(&server_x25519.public_key()),
            "018ff6f1-0000-7000-8000-000000000002",
            1_700_000_001_000,
        )
        .expect("client hello should be accepted");

        let transcript_input = AuthTranscriptInput {
            role: AuthRole::Client,
            space_id: server_hello.space_id.clone(),
            local_device_id: server_hello.peer_device_id.clone(),
            remote_device_id: server_hello.server_device_id.clone(),
            local_identity_public_key: server_hello.peer_identity_public_key.clone(),
            remote_identity_public_key: server_hello.server_identity_public_key.clone(),
            local_ephemeral_public_key: server_hello.peer_ephemeral_public_key.clone(),
            remote_ephemeral_public_key: server_hello.server_ephemeral_public_key.clone(),
            pairing_context: server_hello.pairing_context.clone(),
        };
        let canonical_transcript =
            canonical_auth_transcript(&transcript_input).expect("transcript should build");
        let signature = client_identity.sign(canonical_transcript.as_bytes());
        let auth_proof = AuthProofPayload {
            role: AuthRole::Client,
            signature_algorithm: SignatureAlgorithm::Ed25519,
            transcript_hash: auth_transcript_hash_base64url(&transcript_input)
                .expect("hash should build"),
            signature: encode_base64url(&signature),
        };
        let auth_proof_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::AuthProof,
            message_id: "018ff6f1-0000-7000-8000-000000000003".to_string(),
            session_counter: 2,
            payload: serde_json::to_value(&auth_proof).expect("proof should serialize"),
        })
        .expect("auth proof should serialize");

        let accepted = accept_pairing_auth_proof(
            PairingServerAuthProofInput {
                invitation_id: server_hello.invitation_id.clone(),
                space_id: server_hello.space_id.clone(),
                peer_device_id: server_hello.peer_device_id.clone(),
                peer_identity_public_key: server_hello.peer_identity_public_key.clone(),
                peer_ephemeral_public_key: server_hello.peer_ephemeral_public_key.clone(),
                server_device_id: server_hello.server_device_id.clone(),
                server_identity_public_key: server_hello.server_identity_public_key.clone(),
                server_ephemeral_public_key: server_hello.server_ephemeral_public_key.clone(),
                pairing_context: server_hello.pairing_context.clone(),
                server_ephemeral_secret: server_x25519.clone(),
            },
            &auth_proof_frame,
            "018ff6f1-0000-7000-8000-000000000004",
        )
        .expect("auth proof should be accepted");

        assert_eq!(accepted.invitation_id, server_hello.invitation_id);
        assert_eq!(accepted.peer_device_id, client_hello.device_id);
        assert_eq!(
            accepted.shared_secret,
            client_x25519.shared_secret(server_x25519.public_key())
        );
        assert_ne!(accepted.session_keys.client_to_server, [0u8; 32]);
        assert_ne!(accepted.session_keys.server_to_client, [0u8; 32]);
        let ProtocolEnvelope::PreAuth(auth_ok) =
            parse_envelope(&accepted.auth_ok_frame).expect("auth ok should parse")
        else {
            panic!("auth ok should be pre-auth");
        };
        assert_eq!(auth_ok.message_type, MessageType::AuthOk);
        assert_eq!(auth_ok.session_counter, 3);
    }

    #[test]
    fn rejects_pairing_auth_proof_with_invalid_signature() {
        let server_x25519 = X25519Secret::from_private_key([7u8; 32]);
        let peer_x25519 = X25519Secret::from_private_key([8u8; 32]);
        let transcript_input = AuthTranscriptInput {
            role: AuthRole::Client,
            space_id: "018ff6ef-c394-7d08-8b99-4b7d10f2767a".to_string(),
            local_device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            remote_device_id: "018ff6f0-0a3b-7815-a4db-3eb6e23d9338".to_string(),
            local_identity_public_key: encode_base64url(
                &crate::crypto::Ed25519Identity::from_seed([9u8; 32]).public_key(),
            ),
            remote_identity_public_key: encode_base64url(&[3u8; 32]),
            local_ephemeral_public_key: encode_base64url(&peer_x25519.public_key()),
            remote_ephemeral_public_key: encode_base64url(&server_x25519.public_key()),
            pairing_context: "pairing-invitation:v1:018ff6f1-0000-7000-8000-000000000005"
                .to_string(),
        };
        let auth_proof = AuthProofPayload {
            role: AuthRole::Client,
            signature_algorithm: SignatureAlgorithm::Ed25519,
            transcript_hash: auth_transcript_hash_base64url(&transcript_input)
                .expect("hash should build"),
            signature: encode_base64url(&[0u8; 64]),
        };
        let auth_proof_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::AuthProof,
            message_id: "018ff6f1-0000-7000-8000-000000000003".to_string(),
            session_counter: 2,
            payload: serde_json::to_value(&auth_proof).expect("proof should serialize"),
        })
        .expect("auth proof should serialize");

        assert_eq!(
            accept_pairing_auth_proof(
                PairingServerAuthProofInput {
                    invitation_id: "018ff6f1-0000-7000-8000-000000000005".to_string(),
                    space_id: transcript_input.space_id,
                    peer_device_id: transcript_input.local_device_id,
                    peer_identity_public_key: transcript_input.local_identity_public_key,
                    peer_ephemeral_public_key: transcript_input.local_ephemeral_public_key,
                    server_device_id: transcript_input.remote_device_id,
                    server_identity_public_key: transcript_input.remote_identity_public_key,
                    server_ephemeral_public_key: transcript_input.remote_ephemeral_public_key,
                    pairing_context: transcript_input.pairing_context,
                    server_ephemeral_secret: server_x25519,
                },
                &auth_proof_frame,
                "018ff6f1-0000-7000-8000-000000000004",
            ),
            Err(PairingError::AuthProofSignatureFailed)
        );
    }

    #[test]
    fn rejects_pairing_client_hello_without_pairing_context() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let payload = decode_invitation_payload(&invitation.invitation);
        let client_hello = HelloPayload {
            space_id: payload.space_id,
            device_id: "018ff6f0-4adf-7d31-a987-3ef2b25d0212".to_string(),
            identity_public_key: encode_base64url(&[1u8; 32]),
            ephemeral_public_key: encode_base64url(&[2u8; 32]),
            capabilities: vec![Capability::TextPlain],
            pairing_context: None,
        };
        let client_hello_frame = serialize_pre_auth_envelope(&PreAuthEnvelope {
            message_type: MessageType::ClientHello,
            message_id: "018ff6f1-0000-7000-8000-000000000001".to_string(),
            session_counter: 0,
            payload: serde_json::to_value(&client_hello).expect("hello should serialize"),
        })
        .expect("client hello should serialize");

        assert_eq!(
            accept_pairing_client_hello(
                &mut connection,
                &mut store,
                &client_hello_frame,
                &encode_base64url(&[3u8; 32]),
                "018ff6f1-0000-7000-8000-000000000002",
                1_700_000_001_000,
            ),
            Err(PairingError::InvalidClientHello)
        );
    }

    #[test]
    fn rejects_expired_or_wrong_secret_invitation_consumption() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let wrong_secret = encode_base64url(&[9u8; PAIRING_SECRET_BYTES]);
        let consumer_device_id = Uuid::now_v7().to_string();

        let wrong_secret_invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_000_500,
        )
        .expect("invitation should be created");
        let wrong_secret_payload = decode_invitation_payload(&wrong_secret_invitation.invitation);
        assert_eq!(
            consume_pairing_invitation(
                &connection,
                &wrong_secret_payload.invitation_id,
                &wrong_secret,
                &consumer_device_id,
                1_700_000_001_000,
            ),
            Err(PairingError::InvalidInvitationSecret)
        );

        let expired_invitation = create_pairing_invitation_for_space(
            &mut connection,
            &mut store,
            &space.space_id,
            1_700_000_010_000,
        )
        .expect("expired candidate should be created");
        let expired_payload = decode_invitation_payload(&expired_invitation.invitation);
        assert_eq!(
            consume_pairing_invitation(
                &connection,
                &expired_payload.invitation_id,
                &expired_payload.pairing_secret,
                &consumer_device_id,
                expired_invitation.expires_at_ms,
            ),
            Err(PairingError::InvitationExpired)
        );
    }

    #[test]
    fn rejects_pairing_invitation_for_unknown_space() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();

        assert_eq!(
            create_pairing_invitation_for_space(
                &mut connection,
                &mut store,
                &Uuid::now_v7().to_string(),
                1_700_000_000_500,
            ),
            Err(PairingError::MissingSpace)
        );
        assert_eq!(
            create_pairing_invitation_for_space(
                &mut connection,
                &mut store,
                "not-a-uuid",
                1_700_000_000_500,
            ),
            Err(PairingError::InvalidSpaceId)
        );
    }

    #[test]
    fn rejects_invalid_space_names_and_missing_keys() {
        let mut connection = open_in_memory_database().expect("database should open");
        let mut store = MemorySecretStore::default();
        assert_eq!(
            create_sync_space(&mut connection, &mut store, " ", 1_700_000_000_000),
            Err(PairingError::InvalidDisplayName)
        );

        let space = create_sync_space(&mut connection, &mut store, "默认空间", 1_700_000_000_000)
            .expect("space should be created");
        let empty_store = MemorySecretStore::default();
        assert_eq!(
            load_space_key(
                &connection,
                &empty_store,
                Uuid::parse_str(&space.space_id).expect("space id should parse"),
            ),
            Err(PairingError::MissingSpaceKey)
        );
    }

    #[test]
    fn generated_space_keys_are_not_constant() {
        let first = random_space_key().expect("random should work");
        let second = random_space_key().expect("random should work");
        assert_ne!(first, second);
    }

    fn decode_base64url_pairing_secret(value: &str) -> Vec<u8> {
        URL_SAFE_NO_PAD
            .decode(value)
            .expect("pairing secret should be base64url")
    }
}
