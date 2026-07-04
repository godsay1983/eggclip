use std::{fmt, path::Path};

#[cfg(test)]
use std::collections::HashMap;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    clipboard,
    crypto::{decode_base64url, encode_base64url},
    identity::{ensure_local_device_identity, IdentityError},
    secret_store::{SecretBytesStore, SecretStoreError},
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{
            PairingInvitationRecord, PairingInvitationRepository, PairingInvitationState,
            SpaceRecord, SpaceRepository,
        },
    },
    sync::{Space, SpaceState},
};

pub const SPACE_KEY_BYTES: usize = 32;
pub const PAIRING_SECRET_BYTES: usize = 32;
pub const INITIAL_SPACE_KEY_VERSION: u32 = 1;
pub const PAIRING_INVITATION_TTL_MS: u64 = 5 * 60 * 1000;
pub const DEFAULT_SPACE_DISPLAY_NAME: &str = "默认空间";
const PAIRING_INVITATION_EXPIRY_SWEEP_SECONDS: u64 = 60;

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
pub struct PairingInvitationSummary {
    pub invitation_id: String,
    pub space_id: String,
    pub space_display_name: String,
    pub invitation: String,
    pub expires_at_ms: u64,
    pub expires_in_seconds: u64,
    pub issuer_device_name: String,
    pub issuer_device_id: String,
    pub issuer_short_fingerprint: String,
    pub confirmation_code: String,
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
    Identity(String),
    InvalidInvitation,
    InvitationMissing,
    InvitationExpired,
    InvitationConsumed,
    InvalidInvitationSecret,
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
            PairingError::Identity(message) => write!(formatter, "identity error: {message}"),
            PairingError::InvalidInvitation => formatter.write_str("invalid pairing invitation"),
            PairingError::InvitationMissing => formatter.write_str("pairing invitation missing"),
            PairingError::InvitationExpired => formatter.write_str("pairing invitation expired"),
            PairingError::InvitationConsumed => formatter.write_str("pairing invitation consumed"),
            PairingError::InvalidInvitationSecret => {
                formatter.write_str("invalid pairing invitation secret")
            }
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
pub fn create_pairing_invitation(
    app: tauri::AppHandle,
    space_id: String,
) -> Result<PairingInvitationSummary, String> {
    let path = database_path(&app)?;
    #[cfg(windows)]
    let mut store = crate::secret_store::WindowsCredentialSecretStore;
    #[cfg(not(windows))]
    let mut store = crate::secret_store::UnavailableSecretStore;

    create_pairing_invitation_at_path(&path, &mut store, &space_id, now_ms()?)
        .map_err(|error| format!("无法生成配对邀请：{error}"))
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
        .map(|record| SyncSpaceSummary {
            space_id: record.space.space_id.to_string(),
            display_name: record.space.display_name,
            key_version: record.space.key_version,
            space_key_ref: record.encrypted_space_key_ref.unwrap_or_default(),
            created_at_ms: record.space.created_at,
        })
        .collect())
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
    };
    let payload_json =
        serde_json::to_vec(&payload).map_err(|error| PairingError::Serialize(error.to_string()))?;
    let invitation = format!(
        "eggclip://pair?p={}",
        URL_SAFE_NO_PAD.encode(payload_json.as_slice())
    );
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

fn normalize_space_display_name(display_name: &str) -> Result<String, PairingError> {
    let normalized = display_name.trim();
    if normalized.is_empty() || normalized.chars().count() > 64 {
        return Err(PairingError::InvalidDisplayName);
    }
    Ok(normalized.to_string())
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
    Ok(())
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
