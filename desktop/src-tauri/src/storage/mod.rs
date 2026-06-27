use std::{path::Path, time::Duration};

use rusqlite::{params, Connection, OptionalExtension};

pub mod repositories;

pub const CURRENT_SCHEMA_VERSION: i64 = 1;
pub const BUSY_TIMEOUT_MS: u64 = 5_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppliedMigration {
    pub version: i64,
    pub name: &'static str,
}

#[derive(Debug)]
struct Migration {
    version: i64,
    name: &'static str,
    sql: &'static str,
}

const MIGRATIONS: &[Migration] = &[Migration {
    version: 1,
    name: "initial_local_sync_schema",
    sql: r#"
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS spaces (
  space_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  encrypted_space_key_ref TEXT,
  key_version INTEGER NOT NULL DEFAULT 1,
  state TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  device_id TEXT PRIMARY KEY,
  space_id TEXT NOT NULL REFERENCES spaces(space_id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  identity_public_key TEXT NOT NULL,
  trust_state TEXT NOT NULL,
  connection_state TEXT NOT NULL,
  paired_at INTEGER,
  last_seen_at INTEGER,
  revoked_at INTEGER
);

CREATE TABLE IF NOT EXISTS clipboard_items (
  item_id TEXT PRIMARY KEY,
  space_id TEXT NOT NULL REFERENCES spaces(space_id) ON DELETE CASCADE,
  origin_device_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  origin_seq INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  content_type TEXT NOT NULL,
  content_length INTEGER NOT NULL,
  content_digest TEXT NOT NULL,
  encrypted_content BLOB,
  created_at INTEGER NOT NULL,
  received_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  deleted_at INTEGER,
  UNIQUE(origin_device_id, origin_seq),
  UNIQUE(space_id, content_digest, origin_device_id, origin_seq)
);

CREATE TABLE IF NOT EXISTS sync_heads (
  space_id TEXT NOT NULL REFERENCES spaces(space_id) ON DELETE CASCADE,
  peer_device_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  origin_device_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  highest_origin_seq INTEGER NOT NULL,
  minimum_available INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(space_id, peer_device_id, origin_device_id)
);

CREATE TABLE IF NOT EXISTS app_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_clipboard_items_space_hlc
  ON clipboard_items(space_id, hlc DESC, item_id DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_clipboard_items_retention
  ON clipboard_items(space_id, expires_at, received_at)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_devices_space_trust
  ON devices(space_id, trust_state, connection_state);
"#,
}];

pub fn open_database(path: impl AsRef<Path>) -> rusqlite::Result<Connection> {
    let mut connection = Connection::open(path)?;
    configure_connection(&connection)?;
    migrate(&mut connection)?;
    Ok(connection)
}

pub fn open_in_memory_database() -> rusqlite::Result<Connection> {
    let mut connection = Connection::open_in_memory()?;
    configure_connection(&connection)?;
    migrate(&mut connection)?;
    Ok(connection)
}

pub fn configure_connection(connection: &Connection) -> rusqlite::Result<()> {
    connection.busy_timeout(Duration::from_millis(BUSY_TIMEOUT_MS))?;
    connection.pragma_update(None, "foreign_keys", "ON")?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    connection.pragma_update(None, "synchronous", "NORMAL")?;
    Ok(())
}

pub fn migrate(connection: &mut Connection) -> rusqlite::Result<Vec<AppliedMigration>> {
    configure_connection(connection)?;
    let transaction = connection.transaction()?;
    transaction.execute_batch(
        "CREATE TABLE IF NOT EXISTS schema_migrations (
          version INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          applied_at INTEGER NOT NULL
        );",
    )?;

    let mut applied = Vec::new();
    for migration in MIGRATIONS {
        let exists: Option<i64> = transaction
            .query_row(
                "SELECT version FROM schema_migrations WHERE version = ?1",
                params![migration.version],
                |row| row.get(0),
            )
            .optional()?;
        if exists.is_some() {
            continue;
        }
        transaction.execute_batch(migration.sql)?;
        transaction.execute(
            "INSERT INTO schema_migrations(version, name, applied_at)
             VALUES (?1, ?2, CAST(strftime('%s', 'now') AS INTEGER) * 1000)",
            params![migration.version, migration.name],
        )?;
        applied.push(AppliedMigration {
            version: migration.version,
            name: migration.name,
        });
    }

    transaction.pragma_update(None, "user_version", CURRENT_SCHEMA_VERSION)?;
    transaction.commit()?;
    Ok(applied)
}

pub fn applied_schema_version(connection: &Connection) -> rusqlite::Result<i64> {
    connection.query_row("PRAGMA user_version", [], |row| row.get(0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    const EXPECTED_TABLES: &[&str] = &[
        "app_metadata",
        "clipboard_items",
        "devices",
        "schema_migrations",
        "spaces",
        "sync_heads",
    ];

    #[test]
    fn initializes_fresh_database_with_required_tables_and_pragmas() {
        let connection = open_in_memory_database().expect("database should initialize");

        for table in EXPECTED_TABLES {
            let exists: i64 = connection
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
                    params![table],
                    |row| row.get(0),
                )
                .expect("table lookup should succeed");
            assert_eq!(exists, 1, "{table} table should exist");
        }

        let foreign_keys: i64 = connection
            .query_row("PRAGMA foreign_keys", [], |row| row.get(0))
            .expect("foreign_keys pragma should be readable");
        let busy_timeout: i64 = connection
            .query_row("PRAGMA busy_timeout", [], |row| row.get(0))
            .expect("busy_timeout pragma should be readable");

        assert_eq!(foreign_keys, 1);
        assert_eq!(busy_timeout, BUSY_TIMEOUT_MS as i64);
        assert_eq!(
            applied_schema_version(&connection),
            Ok(CURRENT_SCHEMA_VERSION)
        );
    }

    #[test]
    fn migrations_are_transactional_and_idempotent() {
        let mut connection = Connection::open_in_memory().expect("database should open");
        configure_connection(&connection).expect("database should configure");

        let first = migrate(&mut connection).expect("first migration should succeed");
        let second = migrate(&mut connection).expect("second migration should succeed");
        let migration_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
                row.get(0)
            })
            .expect("migration count should be readable");

        assert_eq!(first.len(), 1);
        assert_eq!(first[0].version, CURRENT_SCHEMA_VERSION);
        assert!(second.is_empty());
        assert_eq!(migration_count, 1);
    }

    #[test]
    fn schema_accepts_core_records_and_enforces_constraints() {
        let connection = open_in_memory_database().expect("database should initialize");
        let space_id = Uuid::now_v7().to_string();
        let local_device_id = Uuid::now_v7().to_string();
        let peer_device_id = Uuid::now_v7().to_string();
        let item_id = Uuid::now_v7().to_string();

        connection
            .execute(
                "INSERT INTO spaces(space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at)
                 VALUES (?1, '默认空间', 'credential://space-key', 1, 'active', 1700000000000, 1700000000000)",
                params![space_id],
            )
            .expect("space insert should succeed");
        for device_id in [&local_device_id, &peer_device_id] {
            connection
                .execute(
                    "INSERT INTO devices(device_id, space_id, display_name, identity_public_key, trust_state, connection_state, paired_at)
                     VALUES (?1, ?2, '设备', 'pubkey-ref', 'trusted', 'offline', 1700000000000)",
                    params![device_id, space_id],
                )
                .expect("device insert should succeed");
        }

        connection
            .execute(
                "INSERT INTO clipboard_items(
                  item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                  content_length, content_digest, encrypted_content, created_at, received_at, expires_at
                ) VALUES (?1, ?2, ?3, 1, '0000018bcfe56864-0000', 'text/plain',
                  11, 'hmac-digest-ref', x'001122', 1700000000100, 1700000000100, 1700604800100)",
                params![item_id, space_id, local_device_id],
            )
            .expect("clipboard item insert should succeed");
        let duplicate = connection.execute(
            "INSERT INTO clipboard_items(
              item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
              content_length, content_digest, encrypted_content, created_at, received_at, expires_at
            ) VALUES (?1, ?2, ?3, 1, '0000018bcfe56865-0000', 'text/plain',
              11, 'other-hmac-digest-ref', x'001122', 1700000000101, 1700000000101, 1700604800101)",
            params![Uuid::now_v7().to_string(), space_id, local_device_id],
        );
        assert!(duplicate.is_err());

        connection
            .execute(
                "INSERT INTO sync_heads(space_id, peer_device_id, origin_device_id, highest_origin_seq, minimum_available, updated_at)
                 VALUES (?1, ?2, ?3, 1, 1, 1700000000200)",
                params![space_id, peer_device_id, local_device_id],
            )
            .expect("sync head insert should succeed");
    }

    #[test]
    fn file_database_uses_wal_after_open() {
        let path = std::env::temp_dir().join(format!("eggclip-storage-{}.db", Uuid::now_v7()));
        let connection = open_database(&path).expect("file database should open");
        let journal_mode: String = connection
            .query_row("PRAGMA journal_mode", [], |row| row.get(0))
            .expect("journal mode should be readable");
        drop(connection);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("db-shm"));
        let _ = std::fs::remove_file(path.with_extension("db-wal"));

        assert_eq!(journal_mode.to_ascii_lowercase(), "wal");
    }
}
