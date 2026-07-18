use std::{path::Path, time::Duration};

use rusqlite::{params, Connection, OptionalExtension};

pub mod repositories;

pub const CURRENT_SCHEMA_VERSION: i64 = 4;
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

const MIGRATIONS: &[Migration] = &[
    Migration {
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
    },
    Migration {
        version: 2,
        name: "pairing_invitation_registry",
        sql: r#"
CREATE TABLE IF NOT EXISTS pairing_invitations (
  invitation_id TEXT PRIMARY KEY,
  space_id TEXT NOT NULL REFERENCES spaces(space_id) ON DELETE CASCADE,
  issuer_device_id TEXT NOT NULL,
  secret_verifier TEXT NOT NULL,
  state TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  consumed_at INTEGER,
  consumed_by_device_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_pairing_invitations_space_state
  ON pairing_invitations(space_id, state, expires_at);
"#,
    },
    Migration {
        version: 3,
        name: "space_membership_and_trusted_routes",
        sql: r#"
ALTER TABLE spaces ADD COLUMN local_role TEXT NOT NULL DEFAULT 'owner'
  CHECK(local_role IN ('owner', 'member'));

ALTER TABLE clipboard_items RENAME TO clipboard_items_v2;
ALTER TABLE sync_heads RENAME TO sync_heads_v2;
ALTER TABLE devices RENAME TO devices_v2;

CREATE TABLE device_identities (
  device_id TEXT PRIMARY KEY,
  identity_public_key TEXT NOT NULL
);

CREATE TABLE space_members (
  space_id TEXT NOT NULL REFERENCES spaces(space_id) ON DELETE CASCADE,
  device_id TEXT NOT NULL REFERENCES device_identities(device_id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  trust_state TEXT NOT NULL,
  connection_state TEXT NOT NULL,
  route_role TEXT NOT NULL DEFAULT 'acceptOnly'
    CHECK(route_role IN ('acceptOnly', 'dialCoordinator')),
  last_successful_host TEXT,
  last_successful_port INTEGER,
  paired_at INTEGER,
  last_seen_at INTEGER,
  revoked_at INTEGER,
  PRIMARY KEY(space_id, device_id),
  CHECK(
    (last_successful_host IS NULL AND last_successful_port IS NULL)
    OR
    (last_successful_host IS NOT NULL AND last_successful_port IS NOT NULL
      AND last_successful_port BETWEEN 1 AND 65535)
  )
);

INSERT INTO device_identities(device_id, identity_public_key)
SELECT device_id, identity_public_key FROM devices_v2;

INSERT INTO space_members(
  space_id, device_id, display_name, trust_state, connection_state,
  route_role, last_successful_host, last_successful_port,
  paired_at, last_seen_at, revoked_at
)
SELECT
  space_id, device_id, display_name, trust_state, connection_state,
  'acceptOnly', NULL, NULL, paired_at, last_seen_at, revoked_at
FROM devices_v2;

-- The v2 schema referenced devices only by device_id. It therefore allowed an
-- item or sync head to name a device whose single devices.space_id belonged to
-- another space (notably the internal local-history member). Materialize those
-- missing memberships before installing composite foreign keys.
INSERT OR IGNORE INTO space_members(
  space_id, device_id, display_name, trust_state, connection_state,
  route_role, last_successful_host, last_successful_port,
  paired_at, last_seen_at, revoked_at
)
SELECT DISTINCT
  c.space_id, d.device_id, d.display_name, d.trust_state, 'offline',
  'acceptOnly', NULL, NULL, d.paired_at, d.last_seen_at, d.revoked_at
FROM clipboard_items_v2 c
JOIN devices_v2 d ON d.device_id = c.origin_device_id;

INSERT OR IGNORE INTO space_members(
  space_id, device_id, display_name, trust_state, connection_state,
  route_role, last_successful_host, last_successful_port,
  paired_at, last_seen_at, revoked_at
)
SELECT DISTINCT
  h.space_id, d.device_id, d.display_name, d.trust_state, 'offline',
  'acceptOnly', NULL, NULL, d.paired_at, d.last_seen_at, d.revoked_at
FROM sync_heads_v2 h
JOIN devices_v2 d ON d.device_id IN (h.peer_device_id, h.origin_device_id);

CREATE TABLE clipboard_items (
  item_id TEXT PRIMARY KEY,
  space_id TEXT NOT NULL REFERENCES spaces(space_id) ON DELETE CASCADE,
  origin_device_id TEXT NOT NULL,
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
  FOREIGN KEY(space_id, origin_device_id)
    REFERENCES space_members(space_id, device_id) ON DELETE CASCADE,
  UNIQUE(space_id, origin_device_id, origin_seq),
  UNIQUE(space_id, content_digest, origin_device_id, origin_seq)
);

INSERT INTO clipboard_items(
  item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
  content_length, content_digest, encrypted_content, created_at,
  received_at, expires_at, deleted_at
)
SELECT
  item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
  content_length, content_digest, encrypted_content, created_at,
  received_at, expires_at, deleted_at
FROM clipboard_items_v2;

CREATE TABLE sync_heads (
  space_id TEXT NOT NULL REFERENCES spaces(space_id) ON DELETE CASCADE,
  peer_device_id TEXT NOT NULL,
  origin_device_id TEXT NOT NULL,
  highest_origin_seq INTEGER NOT NULL,
  minimum_available INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(space_id, peer_device_id, origin_device_id),
  FOREIGN KEY(space_id, peer_device_id)
    REFERENCES space_members(space_id, device_id) ON DELETE CASCADE,
  FOREIGN KEY(space_id, origin_device_id)
    REFERENCES space_members(space_id, device_id) ON DELETE CASCADE
);

INSERT INTO sync_heads(
  space_id, peer_device_id, origin_device_id,
  highest_origin_seq, minimum_available, updated_at
)
SELECT
  space_id, peer_device_id, origin_device_id,
  highest_origin_seq, minimum_available, updated_at
FROM sync_heads_v2;

DROP TABLE clipboard_items_v2;
DROP TABLE sync_heads_v2;
DROP TABLE devices_v2;

CREATE INDEX idx_clipboard_items_space_hlc
  ON clipboard_items(space_id, hlc DESC, item_id DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_clipboard_items_retention
  ON clipboard_items(space_id, expires_at, received_at)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_space_members_space_trust
  ON space_members(space_id, trust_state, connection_state);

CREATE INDEX idx_space_members_device
  ON space_members(device_id, space_id);

CREATE INDEX idx_space_members_dial_route
  ON space_members(route_role, trust_state, revoked_at)
  WHERE route_role = 'dialCoordinator';
"#,
    },
    Migration {
        version: 4,
        name: "localized_generated_display_names",
        sql: r#"
ALTER TABLE spaces ADD COLUMN name_origin TEXT NOT NULL DEFAULT 'custom'
  CHECK(name_origin IN ('generated', 'custom'));

ALTER TABLE space_members ADD COLUMN name_origin TEXT NOT NULL DEFAULT 'custom'
  CHECK(name_origin IN ('generated', 'custom'));

UPDATE spaces
SET name_origin = 'generated'
WHERE display_name IN ('默认空间', '本机历史')
   OR (
     display_name LIKE '同步空间 %'
     AND CAST(substr(display_name, 6) AS INTEGER) > 0
     AND display_name = '同步空间 ' || CAST(CAST(substr(display_name, 6) AS INTEGER) AS TEXT)
   );

UPDATE space_members
SET name_origin = 'generated'
WHERE display_name IN ('Windows', 'HarmonyOS', 'Windows 桌面')
   OR display_name GLOB 'EggClip 设备 #[A-Za-z0-9_-]*'
   OR display_name GLOB 'HarmonyOS 设备 #[A-Za-z0-9_-]*'
   OR display_name GLOB 'Windows 设备 #[A-Za-z0-9_-]*';
"#,
    },
];

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
        "device_identities",
        "pairing_invitations",
        "schema_migrations",
        "space_members",
        "spaces",
        "sync_heads",
    ];
    const EXPECTED_INDEXES: &[&str] = &[
        "idx_clipboard_items_retention",
        "idx_clipboard_items_space_hlc",
        "idx_pairing_invitations_space_state",
        "idx_space_members_device",
        "idx_space_members_dial_route",
        "idx_space_members_space_trust",
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
        for index in EXPECTED_INDEXES {
            let exists: i64 = connection
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?1",
                    params![index],
                    |row| row.get(0),
                )
                .expect("index lookup should succeed");
            assert_eq!(exists, 1, "{index} index should exist");
        }

        let foreign_keys: i64 = connection
            .query_row("PRAGMA foreign_keys", [], |row| row.get(0))
            .expect("foreign_keys pragma should be readable");
        let busy_timeout: i64 = connection
            .query_row("PRAGMA busy_timeout", [], |row| row.get(0))
            .expect("busy_timeout pragma should be readable");
        let foreign_key_errors: i64 = connection
            .query_row("SELECT COUNT(*) FROM pragma_foreign_key_check", [], |row| {
                row.get(0)
            })
            .expect("foreign key check should succeed");

        assert_eq!(foreign_keys, 1);
        assert_eq!(busy_timeout, BUSY_TIMEOUT_MS as i64);
        assert_eq!(foreign_key_errors, 0);
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

        assert_eq!(first.len(), MIGRATIONS.len());
        assert_eq!(
            first.last().map(|migration| migration.version),
            Some(CURRENT_SCHEMA_VERSION)
        );
        assert!(second.is_empty());
        assert_eq!(migration_count, MIGRATIONS.len() as i64);
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
                "INSERT INTO spaces(space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at, local_role)
                 VALUES (?1, '默认空间', 'credential://space-key', 1, 'active', 1700000000000, 1700000000000, 'owner')",
                params![space_id],
            )
            .expect("space insert should succeed");
        for device_id in [&local_device_id, &peer_device_id] {
            connection
                .execute(
                    "INSERT INTO device_identities(device_id, identity_public_key)
                     VALUES (?1, ?2)",
                    params![device_id, format!("pubkey-{device_id}")],
                )
                .expect("device identity insert should succeed");
            connection
                .execute(
                    "INSERT INTO space_members(
                       space_id, device_id, display_name, trust_state, connection_state,
                       route_role, paired_at
                     ) VALUES (?2, ?1, '设备', 'trusted', 'offline', 'acceptOnly', 1700000000000)",
                    params![device_id, space_id],
                )
                .expect("space member insert should succeed");
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

        let invalid_route = connection.execute(
            "UPDATE space_members
             SET route_role = 'dialCoordinator', last_successful_host = '192.168.1.2', last_successful_port = NULL
             WHERE space_id = ?1 AND device_id = ?2",
            params![space_id, peer_device_id],
        );
        assert!(invalid_route.is_err());
    }

    #[test]
    fn migration_v3_preserves_v2_rows_and_assigns_safe_roles() {
        let mut connection = Connection::open_in_memory().expect("database should open");
        configure_connection(&connection).expect("database should configure");
        for migration in MIGRATIONS.iter().take(2) {
            connection
                .execute_batch(migration.sql)
                .expect("legacy migration should apply");
            connection
                .execute(
                    "INSERT INTO schema_migrations(version, name, applied_at) VALUES (?1, ?2, 0)",
                    params![migration.version, migration.name],
                )
                .expect("legacy migration should be recorded");
        }
        connection
            .pragma_update(None, "user_version", 2)
            .expect("legacy version");

        let space_id = Uuid::now_v7().to_string();
        let history_space_id = Uuid::now_v7().to_string();
        let local_device_id = Uuid::now_v7().to_string();
        let peer_device_id = Uuid::now_v7().to_string();
        let item_id = Uuid::now_v7().to_string();
        connection
            .execute(
                "INSERT INTO spaces(space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at)
                 VALUES (?1, '旧空间', 'credential://old-key', 2, 'active', 10, 20)",
                params![space_id],
            )
            .expect("legacy space");
        connection
            .execute(
                "INSERT INTO spaces(space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at)
                 VALUES (?1, '本机历史', NULL, 1, 'active', 10, 20)",
                params![history_space_id],
            )
            .expect("legacy history space");
        for (device_id, member_space_id, identity) in [
            (&local_device_id, &history_space_id, "local-public-key"),
            (&peer_device_id, &space_id, "peer-public-key"),
        ] {
            connection
                .execute(
                    "INSERT INTO devices(
                       device_id, space_id, display_name, identity_public_key,
                       trust_state, connection_state, paired_at, last_seen_at
                     ) VALUES (?1, ?2, '旧设备', ?3, 'trusted', 'offline', 30, 40)",
                    params![device_id, member_space_id, identity],
                )
                .expect("legacy device");
        }
        connection
            .execute(
                "INSERT INTO clipboard_items(
                   item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
                   content_length, content_digest, encrypted_content, created_at, received_at, expires_at
                 ) VALUES (?1, ?2, ?3, 7, '000000000000000a-0000', 'text/plain',
                   3, 'digest', x'0102', 10, 11, 12)",
                params![item_id, space_id, local_device_id],
            )
            .expect("legacy item");
        connection
            .execute(
                "INSERT INTO sync_heads(
                   space_id, peer_device_id, origin_device_id,
                   highest_origin_seq, minimum_available, updated_at
                 ) VALUES (?1, ?2, ?3, 7, 1, 50)",
                params![space_id, peer_device_id, local_device_id],
            )
            .expect("legacy sync head");

        let applied = migrate(&mut connection).expect("v3 migration should apply");
        assert_eq!(applied.len(), 2);
        assert_eq!(applied[0].version, 3);
        assert_eq!(applied[1].version, 4);
        assert_eq!(
            connection
                .query_row(
                    "SELECT local_role FROM spaces WHERE space_id = ?1",
                    params![space_id],
                    |row| row.get::<_, String>(0),
                )
                .unwrap(),
            "owner"
        );
        let migrated_member: (String, String, Option<String>, Option<i64>) = connection
            .query_row(
                "SELECT i.identity_public_key, m.route_role,
                        m.last_successful_host, m.last_successful_port
                 FROM space_members m
                 JOIN device_identities i ON i.device_id = m.device_id
                 WHERE m.space_id = ?1 AND m.device_id = ?2",
                params![space_id, peer_device_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("migrated member");
        assert_eq!(
            migrated_member,
            (
                "peer-public-key".to_string(),
                "acceptOnly".to_string(),
                None,
                None
            )
        );
        let item_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE item_id = ?1 AND space_id = ?2",
                params![item_id, space_id],
                |row| row.get(0),
            )
            .unwrap();
        let synthesized_local_member: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM space_members WHERE space_id = ?1 AND device_id = ?2",
                params![space_id, local_device_id],
                |row| row.get(0),
            )
            .unwrap();
        let head_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM sync_heads WHERE space_id = ?1",
                params![space_id],
                |row| row.get(0),
            )
            .unwrap();
        let foreign_key_errors: i64 = connection
            .query_row("SELECT COUNT(*) FROM pragma_foreign_key_check", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(
            (
                item_count,
                head_count,
                synthesized_local_member,
                foreign_key_errors
            ),
            (1, 1, 1, 0)
        );
        assert!(migrate(&mut connection).unwrap().is_empty());
    }

    #[test]
    fn migration_v4_marks_only_known_generated_names_and_preserves_schema_integrity() {
        let mut connection = Connection::open_in_memory().expect("database should open");
        configure_connection(&connection).expect("database should configure");
        for migration in MIGRATIONS.iter().take(3) {
            connection
                .execute_batch(migration.sql)
                .expect("legacy migration should apply");
            connection
                .execute(
                    "INSERT INTO schema_migrations(version, name, applied_at) VALUES (?1, ?2, 0)",
                    params![migration.version, migration.name],
                )
                .expect("legacy migration should be recorded");
        }

        let generated_space_id = Uuid::now_v7().to_string();
        let custom_space_id = Uuid::now_v7().to_string();
        let generated_device_id = Uuid::now_v7().to_string();
        let custom_device_id = Uuid::now_v7().to_string();
        for (space_id, name) in [
            (&generated_space_id, "同步空间 12"),
            (&custom_space_id, "我的默认空间"),
        ] {
            connection
                .execute(
                    "INSERT INTO spaces(space_id, display_name, key_version, state, created_at, updated_at, local_role)
                     VALUES (?1, ?2, 1, 'active', 1, 1, 'owner')",
                    params![space_id, name],
                )
                .expect("legacy space");
        }
        for (device_id, space_id, name) in [
            (
                &generated_device_id,
                &generated_space_id,
                "EggClip 设备 #Abc_123",
            ),
            (
                &custom_device_id,
                &custom_space_id,
                "我的 EggClip 设备 #Abc_123",
            ),
        ] {
            connection
                .execute(
                    "INSERT INTO device_identities(device_id, identity_public_key) VALUES (?1, ?2)",
                    params![device_id, format!("key-{device_id}")],
                )
                .expect("identity");
            connection
                .execute(
                    "INSERT INTO space_members(space_id, device_id, display_name, trust_state, connection_state)
                     VALUES (?1, ?2, ?3, 'trusted', 'offline')",
                    params![space_id, device_id, name],
                )
                .expect("legacy member");
        }

        let applied = migrate(&mut connection).expect("v4 migration should apply");
        assert_eq!(applied.len(), 1);
        assert_eq!(applied[0].version, 4);
        for (table, id_column, generated_id, custom_id) in [
            ("spaces", "space_id", &generated_space_id, &custom_space_id),
            (
                "space_members",
                "device_id",
                &generated_device_id,
                &custom_device_id,
            ),
        ] {
            let generated: String = connection
                .query_row(
                    &format!("SELECT name_origin FROM {table} WHERE {id_column} = ?1"),
                    params![generated_id],
                    |row| row.get(0),
                )
                .unwrap();
            let custom: String = connection
                .query_row(
                    &format!("SELECT name_origin FROM {table} WHERE {id_column} = ?1"),
                    params![custom_id],
                    |row| row.get(0),
                )
                .unwrap();
            assert_eq!(generated, "generated");
            assert_eq!(custom, "custom");
        }
        let foreign_key_errors: i64 = connection
            .query_row("SELECT COUNT(*) FROM pragma_foreign_key_check", [], |row| {
                row.get(0)
            })
            .unwrap();
        let member_index: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_space_members_device'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!((foreign_key_errors, member_index), (0, 1));
        assert!(migrate(&mut connection).unwrap().is_empty());
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
