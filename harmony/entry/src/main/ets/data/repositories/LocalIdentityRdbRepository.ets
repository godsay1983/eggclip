import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Database } from '../db/Database';
import {
  INITIAL_ORIGIN_SEQ,
  LOCAL_DEVICE_ID_KEY,
  NEXT_ORIGIN_SEQ_KEY
} from './RepositoryCommands';

export class LocalIdentityRdbRepository {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async getOrCreateDeviceId(updatedAt: number = Date.now()): Promise<string> {
    const store = await Database.getStore(this.context);
    return this.getOrCreateDeviceIdWithStore(store, updatedAt);
  }

  async getOrCreateDeviceIdWithStore(store: relationalStore.RdbStore, updatedAt: number = Date.now()): Promise<string> {
    const existing = await this.metadataValue(store, LOCAL_DEVICE_ID_KEY);
    if (existing !== null && existing.length > 0) {
      return existing;
    }

    const deviceId = util.generateRandomUUID(false).toLowerCase();
    await store.executeSql(
      `INSERT OR IGNORE INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)`,
      [LOCAL_DEVICE_ID_KEY, deviceId, updatedAt]
    );
    const persisted = await this.metadataValue(store, LOCAL_DEVICE_ID_KEY);
    return persisted ?? deviceId;
  }

  async peekNextOriginSeq(): Promise<number> {
    const store = await Database.getStore(this.context);
    return this.peekNextOriginSeqWithStore(store);
  }

  async peekNextOriginSeqWithStore(store: relationalStore.RdbStore): Promise<number> {
    const existing = await this.metadataValue(store, NEXT_ORIGIN_SEQ_KEY);
    if (existing === null || existing.length === 0) {
      return INITIAL_ORIGIN_SEQ;
    }
    const parsed = Number.parseInt(existing, 10);
    if (!Number.isSafeInteger(parsed) || parsed < INITIAL_ORIGIN_SEQ) {
      throw new Error('Invalid local origin sequence metadata');
    }
    return parsed;
  }

  async allocateOriginSeq(updatedAt: number = Date.now()): Promise<number> {
    const store = await Database.getStore(this.context);
    return this.allocateOriginSeqWithStore(store, updatedAt);
  }

  async allocateOriginSeqWithStore(store: relationalStore.RdbStore, updatedAt: number = Date.now()): Promise<number> {
    store.beginTransaction();
    try {
      await store.executeSql(
        `INSERT OR IGNORE INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)`,
        [NEXT_ORIGIN_SEQ_KEY, INITIAL_ORIGIN_SEQ.toString(), updatedAt]
      );
      const current = await this.peekNextOriginSeqWithStore(store);
      if (!Number.isSafeInteger(current + 1)) {
        throw new Error('Local origin sequence overflow');
      }
      await store.executeSql(
        `UPDATE app_metadata SET value = ?, updated_at = ? WHERE key = ? AND value = ?`,
        [(current + 1).toString(), updatedAt, NEXT_ORIGIN_SEQ_KEY, current.toString()]
      );
      store.commit();
      return current;
    } catch (error) {
      store.rollBack();
      throw error;
    }
  }

  private async metadataValue(store: relationalStore.RdbStore, key: string): Promise<string | null> {
    const resultSet = await store.querySql(
      `SELECT value FROM app_metadata WHERE key = ? LIMIT 1`,
      [key]
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return resultSet.getString(resultSet.getColumnIndex('value'));
    } finally {
      resultSet.close();
    }
  }
}
