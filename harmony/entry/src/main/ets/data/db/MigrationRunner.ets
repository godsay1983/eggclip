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
