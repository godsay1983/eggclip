use std::{fmt, path::Path};

#[cfg(test)]
use std::collections::HashMap;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    crypto::encode_base64url,
    identity::{ensure_local_device_identity, IdentityError},
    secret_store::{SecretBytesStore, SecretStoreError},
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{SpaceRecord, SpaceRepository},
    },
    sync::{Space, SpaceState},
};

pub const SPACE_KEY_BYTES: usize = 32;
pub const PAIRING_SECRET_BYTES: usize = 32;
pub const INITIAL_SPACE_KEY_VERSION: u32 = 1;
pub const PAIRING_INVITATION_TTL_MS: u64 = 5 * 60 * 1000;

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
    pub space_id: String,
    pub space_display_name: String,
    pub invitation: String,
    pub expires_at_ms: u64,
    pub expires_in_seconds: u64,
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
    space_id: String,
    space_key_version: u32,
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
    let identity = ensure_local_device_identity(connection, secret_store, now_ms)
        .map_err(pairing_identity_error)?;
    let mut pairing_secret = random_pairing_secret()?;
    let pairing_secret_encoded = encode_base64url(&pairing_secret);
    let expires_at_ms = now_ms.saturating_add(PAIRING_INVITATION_TTL_MS);
    let payload = PairingInvitationPayload {
        app: "eggclip".to_string(),
        version: 1,
        kind: "pairingInvitation".to_string(),
        space_id: space.space.space_id.to_string(),
        space_key_version: space.space.key_version,
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

    Ok(PairingInvitationSummary {
        space_id: space.space.space_id.to_string(),
        space_display_name: space.space.display_name,
        invitation,
        expires_at_ms,
        expires_in_seconds: PAIRING_INVITATION_TTL_MS / 1000,
        issuer_device_id: identity.device_id,
        issuer_short_fingerprint: identity.identity_public_key.chars().take(8).collect(),
        confirmation_code,
    })
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
        assert_eq!(payload.space_id, space.space_id);
        assert_eq!(payload.space_key_version, INITIAL_SPACE_KEY_VERSION);
        assert_eq!(
            decode_base64url_pairing_secret(&payload.pairing_secret).len(),
            PAIRING_SECRET_BYTES
        );
        assert_eq!(payload.expires_at_ms, invitation.expires_at_ms);
        assert_eq!(payload.issuer_device_id, invitation.issuer_device_id);
        assert!(payload.issuer_identity_public_key.len() >= 43);
        assert_eq!(invitation.confirmation_code.len(), 6);
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
