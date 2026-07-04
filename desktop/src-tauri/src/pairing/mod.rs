use std::{fmt, path::Path};

#[cfg(test)]
use std::collections::HashMap;

use rusqlite::Connection;
use serde::Serialize;
use uuid::Uuid;

use crate::{
    secret_store::{SecretBytesStore, SecretStoreError},
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{SpaceRecord, SpaceRepository},
    },
    sync::{Space, SpaceState},
};

pub const SPACE_KEY_BYTES: usize = 32;
pub const INITIAL_SPACE_KEY_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncSpaceSummary {
    pub space_id: String,
    pub display_name: String,
    pub key_version: u32,
    pub space_key_ref: String,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingError {
    Database(String),
    KeyStore(String),
    RandomUnavailable,
    InvalidDisplayName,
    MissingSpaceKeyRef,
    MissingSpaceKey,
}

impl fmt::Display for PairingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PairingError::Database(message) => write!(formatter, "database error: {message}"),
            PairingError::KeyStore(message) => write!(formatter, "key store error: {message}"),
            PairingError::RandomUnavailable => formatter.write_str("secure random unavailable"),
            PairingError::InvalidDisplayName => formatter.write_str("invalid space display name"),
            PairingError::MissingSpaceKeyRef => formatter.write_str("space key reference missing"),
            PairingError::MissingSpaceKey => formatter.write_str("space key missing"),
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

fn space_key_ref(space_id: Uuid, key_version: u32) -> String {
    format!("credential://eggclip/space-key/{space_id}/v{key_version}")
}

fn pairing_secret_store_error(error: SecretStoreError) -> PairingError {
    PairingError::KeyStore(error.to_string())
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
}
