use std::{fmt, path::Path};

#[cfg(test)]
use std::collections::HashMap;

use rusqlite::Connection;
use serde::Serialize;
use uuid::Uuid;

use crate::{
    crypto::{
        encode_base64url, Ed25519Identity, ED25519_PRIVATE_SEED_BYTES, ED25519_PUBLIC_KEY_BYTES,
    },
    settings::{database_path, now_ms},
    storage::{
        open_database,
        repositories::{LocalIdentityRepository, SettingsRepository},
    },
};

const LOCAL_IDENTITY_PUBLIC_KEY_KEY: &str = "localIdentityPublicKey";
const LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY: &str = "localIdentityPrivateKeyRef";
const LOCAL_IDENTITY_CREATED_AT_KEY: &str = "localIdentityCreatedAt";

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalDeviceIdentitySummary {
    pub device_id: String,
    pub identity_public_key: String,
    pub private_key_ref: String,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IdentityError {
    Database(String),
    KeyStore(String),
    RandomUnavailable,
    MissingPrivateKey,
    InvalidMetadata(String),
}

impl fmt::Display for IdentityError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            IdentityError::Database(message) => write!(formatter, "database error: {message}"),
            IdentityError::KeyStore(message) => write!(formatter, "key store error: {message}"),
            IdentityError::RandomUnavailable => formatter.write_str("secure random unavailable"),
            IdentityError::MissingPrivateKey => formatter.write_str("identity private key missing"),
            IdentityError::InvalidMetadata(field) => {
                write!(formatter, "invalid identity metadata: {field}")
            }
        }
    }
}

impl std::error::Error for IdentityError {}

pub trait IdentitySecretStore {
    fn load_seed(
        &self,
        private_key_ref: &str,
    ) -> Result<Option<[u8; ED25519_PRIVATE_SEED_BYTES]>, IdentityError>;

    fn save_seed(
        &mut self,
        private_key_ref: &str,
        seed: [u8; ED25519_PRIVATE_SEED_BYTES],
    ) -> Result<(), IdentityError>;
}

#[tauri::command]
pub fn load_local_device_identity(
    app: tauri::AppHandle,
) -> Result<LocalDeviceIdentitySummary, String> {
    let path = database_path(&app)?;
    let mut store = UnavailableIdentitySecretStore;
    ensure_local_device_identity_at_path(&path, &mut store, now_ms()?)
        .map_err(|error| format!("无法加载本机设备身份：{error}"))
}

pub fn ensure_local_device_identity_at_path<S: IdentitySecretStore>(
    path: &Path,
    secret_store: &mut S,
    now_ms: u64,
) -> Result<LocalDeviceIdentitySummary, IdentityError> {
    let mut connection =
        open_database(path).map_err(|error| IdentityError::Database(error.to_string()))?;
    ensure_local_device_identity(&mut connection, secret_store, now_ms)
}

pub fn ensure_local_device_identity<S: IdentitySecretStore>(
    connection: &mut Connection,
    secret_store: &mut S,
    now_ms: u64,
) -> Result<LocalDeviceIdentitySummary, IdentityError> {
    let device_id = {
        let mut identity_repository = LocalIdentityRepository::new(connection);
        identity_repository
            .get_or_create_device_id(now_ms)
            .map_err(|error| IdentityError::Database(error.to_string()))?
    };

    let settings = SettingsRepository::new(connection);
    let existing_public_key = settings
        .get(LOCAL_IDENTITY_PUBLIC_KEY_KEY)
        .map_err(|error| IdentityError::Database(error.to_string()))?;
    let existing_private_key_ref = settings
        .get(LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY)
        .map_err(|error| IdentityError::Database(error.to_string()))?;
    let existing_created_at = settings
        .get(LOCAL_IDENTITY_CREATED_AT_KEY)
        .map_err(|error| IdentityError::Database(error.to_string()))?;

    match (
        existing_public_key,
        existing_private_key_ref,
        existing_created_at,
    ) {
        (Some(identity_public_key), Some(private_key_ref), Some(created_at)) => {
            validate_public_key(&identity_public_key)?;
            let created_at_ms = parse_created_at(&created_at)?;
            if secret_store.load_seed(&private_key_ref)?.is_none() {
                return Err(IdentityError::MissingPrivateKey);
            }
            Ok(LocalDeviceIdentitySummary {
                device_id: device_id.to_string(),
                identity_public_key,
                private_key_ref,
                created_at_ms,
            })
        }
        (None, None, None) => create_local_identity(connection, secret_store, device_id, now_ms),
        _ => Err(IdentityError::InvalidMetadata(
            "partial identity metadata".to_string(),
        )),
    }
}

fn create_local_identity<S: IdentitySecretStore>(
    connection: &Connection,
    secret_store: &mut S,
    device_id: Uuid,
    now_ms: u64,
) -> Result<LocalDeviceIdentitySummary, IdentityError> {
    let seed = random_ed25519_seed()?;
    let identity = Ed25519Identity::from_seed(seed);
    let public_key = identity.public_key();
    let identity_public_key = encode_base64url(&public_key);
    let private_key_ref = format!("credential://eggclip/device-identity/{device_id}");

    secret_store.save_seed(&private_key_ref, seed)?;

    let settings = SettingsRepository::new(connection);
    settings
        .set(LOCAL_IDENTITY_PUBLIC_KEY_KEY, &identity_public_key, now_ms)
        .map_err(|error| IdentityError::Database(error.to_string()))?;
    settings
        .set(LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY, &private_key_ref, now_ms)
        .map_err(|error| IdentityError::Database(error.to_string()))?;
    settings
        .set(LOCAL_IDENTITY_CREATED_AT_KEY, &now_ms.to_string(), now_ms)
        .map_err(|error| IdentityError::Database(error.to_string()))?;

    Ok(LocalDeviceIdentitySummary {
        device_id: device_id.to_string(),
        identity_public_key,
        private_key_ref,
        created_at_ms: now_ms,
    })
}

fn random_ed25519_seed() -> Result<[u8; ED25519_PRIVATE_SEED_BYTES], IdentityError> {
    let mut seed = [0u8; ED25519_PRIVATE_SEED_BYTES];
    getrandom::getrandom(&mut seed).map_err(|_| IdentityError::RandomUnavailable)?;
    Ok(seed)
}

fn validate_public_key(value: &str) -> Result<(), IdentityError> {
    let bytes = crate::crypto::decode_base64url(value)
        .map_err(|_| IdentityError::InvalidMetadata("identity public key".to_string()))?;
    if bytes.len() != ED25519_PUBLIC_KEY_BYTES {
        return Err(IdentityError::InvalidMetadata(
            "identity public key length".to_string(),
        ));
    }
    Ok(())
}

fn parse_created_at(value: &str) -> Result<u64, IdentityError> {
    value
        .parse::<u64>()
        .map_err(|_| IdentityError::InvalidMetadata("identity createdAt".to_string()))
}

struct UnavailableIdentitySecretStore;

impl IdentitySecretStore for UnavailableIdentitySecretStore {
    fn load_seed(
        &self,
        _private_key_ref: &str,
    ) -> Result<Option<[u8; ED25519_PRIVATE_SEED_BYTES]>, IdentityError> {
        Err(IdentityError::KeyStore(
            "system credential store is not wired to the Tauri command yet".to_string(),
        ))
    }

    fn save_seed(
        &mut self,
        _private_key_ref: &str,
        _seed: [u8; ED25519_PRIVATE_SEED_BYTES],
    ) -> Result<(), IdentityError> {
        Err(IdentityError::KeyStore(
            "system credential store is not wired to the Tauri command yet".to_string(),
        ))
    }
}

#[cfg(test)]
#[derive(Default)]
struct MemoryIdentitySecretStore {
    seeds: HashMap<String, [u8; ED25519_PRIVATE_SEED_BYTES]>,
}

#[cfg(test)]
impl IdentitySecretStore for MemoryIdentitySecretStore {
    fn load_seed(
        &self,
        private_key_ref: &str,
    ) -> Result<Option<[u8; ED25519_PRIVATE_SEED_BYTES]>, IdentityError> {
        Ok(self.seeds.get(private_key_ref).copied())
    }

    fn save_seed(
        &mut self,
        private_key_ref: &str,
        seed: [u8; ED25519_PRIVATE_SEED_BYTES],
    ) -> Result<(), IdentityError> {
        self.seeds.insert(private_key_ref.to_string(), seed);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_database_path() -> std::path::PathBuf {
        std::env::temp_dir().join(format!("eggclip-identity-{}.db", Uuid::now_v7()))
    }

    fn cleanup_database(path: &Path) {
        let _ = fs::remove_file(path);
        let _ = fs::remove_file(path.with_extension("db-shm"));
        let _ = fs::remove_file(path.with_extension("db-wal"));
    }

    #[test]
    fn creates_random_identity_without_storing_private_seed_in_sqlite() {
        let path = temp_database_path();
        let mut store = MemoryIdentitySecretStore::default();

        let identity = ensure_local_device_identity_at_path(&path, &mut store, 1_700_000_000_000)
            .expect("identity should be created");

        assert_eq!(identity.created_at_ms, 1_700_000_000_000);
        assert!(identity
            .private_key_ref
            .starts_with("credential://eggclip/device-identity/"));
        assert_eq!(
            crate::crypto::decode_base64url(&identity.identity_public_key)
                .unwrap()
                .len(),
            32
        );
        assert!(store
            .load_seed(&identity.private_key_ref)
            .unwrap()
            .is_some());

        let connection = open_database(&path).expect("database should reopen");
        let metadata_values = SettingsRepository::new(&connection)
            .get(LOCAL_IDENTITY_PUBLIC_KEY_KEY)
            .expect("metadata should load")
            .expect("public key should be stored");
        assert_eq!(metadata_values, identity.identity_public_key);
        let stored_refs: Vec<String> = connection
            .prepare("SELECT value FROM app_metadata ORDER BY key")
            .expect("query should prepare")
            .query_map([], |row| row.get::<_, String>(0))
            .expect("query should run")
            .collect::<Result<Vec<_>, _>>()
            .expect("rows should collect");
        cleanup_database(&path);

        for value in stored_refs {
            assert_ne!(
                value,
                crate::crypto::encode_base64url(
                    &store.load_seed(&identity.private_key_ref).unwrap().unwrap()
                )
            );
        }
    }

    #[test]
    fn reloads_existing_identity_from_external_secret_store() {
        let path = temp_database_path();
        let mut store = MemoryIdentitySecretStore::default();

        let first = ensure_local_device_identity_at_path(&path, &mut store, 1_700_000_000_000)
            .expect("identity should be created");
        let second = ensure_local_device_identity_at_path(&path, &mut store, 1_700_000_000_500)
            .expect("identity should reload");
        cleanup_database(&path);

        assert_eq!(second, first);
    }

    #[test]
    fn refuses_identity_metadata_when_private_seed_is_missing() {
        let path = temp_database_path();
        let mut first_store = MemoryIdentitySecretStore::default();
        let identity =
            ensure_local_device_identity_at_path(&path, &mut first_store, 1_700_000_000_000)
                .expect("identity should be created");
        let mut missing_store = MemoryIdentitySecretStore::default();

        let error =
            ensure_local_device_identity_at_path(&path, &mut missing_store, 1_700_000_000_100)
                .expect_err("missing credential should fail");
        cleanup_database(&path);

        assert_eq!(error, IdentityError::MissingPrivateKey);
        assert!(identity.private_key_ref.starts_with("credential://"));
    }

    #[test]
    fn generated_identity_public_keys_are_not_constant() {
        let first_seed = random_ed25519_seed().expect("random should work");
        let second_seed = random_ed25519_seed().expect("random should work");
        let first = Ed25519Identity::from_seed(first_seed);
        let second = Ed25519Identity::from_seed(second_seed);

        assert_ne!(first.public_key(), second.public_key());
    }
}
