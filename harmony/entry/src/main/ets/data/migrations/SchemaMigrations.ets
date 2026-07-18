export const CURRENT_SCHEMA_VERSION: number = 2;
export const DATABASE_NAME: string = 'eggclip.db';

export interface SchemaMigration {
  version: number;
  name: string;
  statements: string[];
}

export const INITIAL_SCHEMA_TABLES: string[] = [
  'schema_migrations',
  'spaces',
  'devices',
  'clipboard_items',
  'sync_heads',
  'app_metadata'
];

export const SCHEMA_MIGRATIONS: SchemaMigration[] = [
  {
    version: 1,
    name: 'initial_local_sync_schema',
    statements: [
      `CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS spaces (
        space_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        encrypted_space_key_ref TEXT,
        key_version INTEGER NOT NULL DEFAULT 1,
        state TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        identity_public_key TEXT NOT NULL,
        trust_state TEXT NOT NULL,
        connection_state TEXT NOT NULL,
        paired_at INTEGER,
        last_seen_at INTEGER,
        revoked_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS clipboard_items (
        item_id TEXT PRIMARY KEY,
        space_id TEXT NOT NULL,
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
        UNIQUE(origin_device_id, origin_seq),
        UNIQUE(space_id, content_digest, origin_device_id, origin_seq)
      )`,
      `CREATE TABLE IF NOT EXISTS sync_heads (
        space_id TEXT NOT NULL,
        peer_device_id TEXT NOT NULL,
        origin_device_id TEXT NOT NULL,
        highest_origin_seq INTEGER NOT NULL,
        minimum_available INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(space_id, peer_device_id, origin_device_id)
      )`,
      `CREATE TABLE IF NOT EXISTS app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE INDEX IF NOT EXISTS idx_clipboard_items_space_hlc
        ON clipboard_items(space_id, hlc DESC, item_id DESC)`,
      `CREATE INDEX IF NOT EXISTS idx_clipboard_items_retention
        ON clipboard_items(space_id, expires_at, received_at)`,
      `CREATE INDEX IF NOT EXISTS idx_devices_space_trust
        ON devices(space_id, trust_state, connection_state)`
    ]
  },
  {
    version: 2,
    name: 'localized_generated_display_names',
    statements: [
      `ALTER TABLE spaces ADD COLUMN name_origin TEXT NOT NULL DEFAULT 'custom'
        CHECK(name_origin IN ('generated', 'custom'))`,
      `ALTER TABLE devices ADD COLUMN name_origin TEXT NOT NULL DEFAULT 'custom'
        CHECK(name_origin IN ('generated', 'custom'))`,
      `UPDATE spaces SET name_origin = 'generated'
        WHERE display_name = '默认空间' OR display_name LIKE '同步空间 #%'
        OR display_name LIKE '同步空间 %'`,
      `UPDATE devices SET name_origin = 'generated'
        WHERE display_name IN ('桌面端', 'Windows 桌面', 'HarmonyOS')
        OR display_name LIKE '桌面端 #%'
        OR display_name LIKE 'EggClip 设备 #%'
        OR display_name LIKE 'HarmonyOS 设备 #%'
        OR display_name LIKE 'Windows 设备 #%'
        OR display_name LIKE 'EggClip Desktop #%'
        OR display_name LIKE 'EggClip device #%'`
    ]
  }
];

export function pendingMigrations(currentVersion: number): SchemaMigration[] {
  return SCHEMA_MIGRATIONS.filter((migration: SchemaMigration) => migration.version > currentVersion);
}

export function isLegacyGeneratedSpaceName(value: string): boolean {
  return value === '默认空间' || value === '本机历史' ||
    /^同步空间 (#)?[A-Za-z0-9_-]+$/.test(value) || /^同步空间 [1-9][0-9]*$/.test(value);
}

export function isLegacyGeneratedDeviceName(value: string): boolean {
  return value === '桌面端' || value === 'Windows 桌面' || value === 'HarmonyOS' ||
    /^(桌面端|EggClip 设备|HarmonyOS 设备|Windows 设备|EggClip Desktop|EggClip device) #[A-Za-z0-9_-]+$/.test(value);
}

export function allSchemaSql(): string[] {
  const statements: string[] = [];
  for (const migration of SCHEMA_MIGRATIONS) {
    statements.push(...migration.statements);
  }
  return statements;
}

export function validateSchemaPlan(): boolean {
  if (SCHEMA_MIGRATIONS.length === 0) {
    return false;
  }
  let previousVersion = 0;
  for (const migration of SCHEMA_MIGRATIONS) {
    if (migration.version <= previousVersion || migration.statements.length === 0) {
      return false;
    }
    previousVersion = migration.version;
  }

  const sql = allSchemaSql().join('\n').toLowerCase();
  for (const table of INITIAL_SCHEMA_TABLES) {
    if (sql.indexOf(`create table if not exists ${table}`) < 0) {
      return false;
    }
  }
  return sql.indexOf('encrypted_content') >= 0 &&
    sql.indexOf(' plaintext ') < 0 &&
    sql.indexOf('unique(origin_device_id, origin_seq)') >= 0;
}
