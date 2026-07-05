import { relationalStore } from '@kit.ArkData';
import {
  CURRENT_SCHEMA_VERSION,
  SCHEMA_MIGRATIONS,
  SchemaMigration,
  pendingMigrations
} from '../migrations/SchemaMigrations';

export class MigrationRunner {
  async migrate(store: relationalStore.RdbStore): Promise<void> {
    await this.ensureMigrationTable(store);
    const currentVersion = await this.currentVersion(store);
    const migrations = pendingMigrations(currentVersion);
    for (const migration of migrations) {
      await this.applyMigration(store, migration);
    }
    await this.ensureBaselineSchema(store);
    await this.ensureBaselineColumns(store);
    store.version = CURRENT_SCHEMA_VERSION;
  }

  private async applyMigration(store: relationalStore.RdbStore, migration: SchemaMigration): Promise<void> {
    store.beginTransaction();
    try {
      for (const statement of migration.statements) {
        await store.executeSql(statement);
      }
      await store.executeSql(
        `INSERT INTO schema_migrations(version, name, applied_at) VALUES (?, ?, ?)`,
        [migration.version, migration.name, Date.now()]
      );
      store.commit();
    } catch (_) {
      store.rollBack();
      throw new Error('RDB migration transaction failed');
    }
  }

  private async ensureMigrationTable(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at INTEGER NOT NULL
      )`
    );
  }

  private async ensureBaselineSchema(store: relationalStore.RdbStore): Promise<void> {
    for (const migration of SCHEMA_MIGRATIONS) {
      for (const statement of migration.statements) {
        await store.executeSql(statement);
      }
    }
  }

  private async ensureBaselineColumns(store: relationalStore.RdbStore): Promise<void> {
    await this.ensureColumns(store, 'spaces', [
      { name: 'display_name', definition: `TEXT NOT NULL DEFAULT '默认空间'` },
      { name: 'encrypted_space_key_ref', definition: 'TEXT' },
      { name: 'key_version', definition: 'INTEGER NOT NULL DEFAULT 1' },
      { name: 'state', definition: `TEXT NOT NULL DEFAULT 'active'` },
      { name: 'created_at', definition: 'INTEGER NOT NULL DEFAULT 0' },
      { name: 'updated_at', definition: 'INTEGER NOT NULL DEFAULT 0' }
    ]);
    await this.ensureColumns(store, 'devices', [
      { name: 'space_id', definition: `TEXT NOT NULL DEFAULT ''` },
      { name: 'display_name', definition: `TEXT NOT NULL DEFAULT ''` },
      { name: 'identity_public_key', definition: `TEXT NOT NULL DEFAULT ''` },
      { name: 'trust_state', definition: `TEXT NOT NULL DEFAULT 'trusted'` },
      { name: 'connection_state', definition: `TEXT NOT NULL DEFAULT 'offline'` },
      { name: 'paired_at', definition: 'INTEGER' },
      { name: 'last_seen_at', definition: 'INTEGER' },
      { name: 'revoked_at', definition: 'INTEGER' }
    ]);
  }

  private async ensureColumns(
    store: relationalStore.RdbStore,
    tableName: string,
    columns: BaselineColumn[]
  ): Promise<void> {
    const existingColumns = await this.tableColumns(store, tableName);
    for (const column of columns) {
      if (existingColumns.indexOf(column.name) < 0) {
        await store.executeSql(`ALTER TABLE ${tableName} ADD COLUMN ${column.name} ${column.definition}`);
      }
    }
  }

  private async tableColumns(store: relationalStore.RdbStore, tableName: string): Promise<string[]> {
    const resultSet = await store.querySql(`PRAGMA table_info(${tableName})`);
    const columns: string[] = [];
    try {
      while (resultSet.goToNextRow()) {
        columns.push(resultSet.getString(resultSet.getColumnIndex('name')));
      }
      return columns;
    } finally {
      resultSet.close();
    }
  }

  private async currentVersion(store: relationalStore.RdbStore): Promise<number> {
    const resultSet = await store.querySql('SELECT MAX(version) AS version FROM schema_migrations');
    try {
      if (!resultSet.goToFirstRow()) {
        return 0;
      }
      const columnIndex = resultSet.getColumnIndex('version');
      if (resultSet.isColumnNull(columnIndex)) {
        return 0;
      }
      return resultSet.getLong(columnIndex);
    } finally {
      resultSet.close();
    }
  }
}

interface BaselineColumn {
  name: string;
  definition: string;
}
