import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Database } from '../db/Database';
import { LocalDeviceIdentityMetadataGateway } from '../../services/crypto/LocalDeviceIdentityService';
import {
  INITIAL_ORIGIN_SEQ,
  LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY,
  LOCAL_IDENTITY_PUBLIC_KEY_KEY,
  LOCAL_DEVICE_ID_KEY,
  NEXT_ORIGIN_SEQ_KEY,
  isValidLocalIdentityPrivateKeyRef,
  isValidLocalIdentityPublicKey
} from './RepositoryCommands';

export class LocalIdentityRdbRepository implements LocalDeviceIdentityMetadataGateway {
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
    if (existing !== null && isUuid(existing)) {
      return existing;
    }

    const deviceId = normalizeUuid(util.generateRandomUUID(false));
    await this.upsertMetadata(store, LOCAL_DEVICE_ID_KEY, deviceId, updatedAt);
    const persisted = await this.metadataValue(store, LOCAL_DEVICE_ID_KEY);
    return persisted ?? deviceId;
  }

  async loadLocalIdentityPublicKey(): Promise<string | null> {
    const store = await Database.getStore(this.context);
    const value = await this.metadataValue(store, LOCAL_IDENTITY_PUBLIC_KEY_KEY);
    if (value === null || !isValidLocalIdentityPublicKey(value)) {
      return null;
    }
    return value;
  }

  async saveLocalIdentityPublicKey(identityPublicKey: string, updatedAt: number = Date.now()): Promise<void> {
    if (!isValidLocalIdentityPublicKey(identityPublicKey)) {
      throw new Error('Invalid local identity public key metadata');
    }
    const store = await Database.getStore(this.context);
    await this.upsertMetadata(store, LOCAL_IDENTITY_PUBLIC_KEY_KEY, identityPublicKey, updatedAt);
  }

  async loadLocalIdentityPrivateKeyRef(): Promise<string | null> {
    const store = await Database.getStore(this.context);
    const value = await this.metadataValue(store, LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY);
    if (value === null || !isValidLocalIdentityPrivateKeyRef(value)) {
      return null;
    }
    return value;
  }

  async saveLocalIdentityPrivateKeyRef(identityPrivateKeyRef: string, updatedAt: number = Date.now()): Promise<void> {
    if (!isValidLocalIdentityPrivateKeyRef(identityPrivateKeyRef)) {
      throw new Error('Invalid local identity private key reference metadata');
    }
    const store = await Database.getStore(this.context);
    await this.upsertMetadata(store, LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY, identityPrivateKeyRef, updatedAt);
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
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('Allocate local origin sequence failed');
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

  private async upsertMetadata(
    store: relationalStore.RdbStore,
    key: string,
    value: string,
    updatedAt: number
  ): Promise<void> {
    await store.executeSql(
      `INSERT INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      [key, value, updatedAt]
    );
  }
}

function normalizeUuid(value: string): string {
  const lower = value.toLowerCase();
  if (isUuid(lower)) {
    return lower;
  }
  const compact = lower.replace(/[^0-9a-f]/g, '');
  const padded = `${compact}${Date.now().toString(16)}00000000000000000000000000000000`.slice(0, 32);
  const variant = /^[89ab]$/.test(padded.charAt(16)) ? padded.charAt(16) : '8';
  return `${padded.slice(0, 8)}-${padded.slice(8, 12)}-4${padded.slice(13, 16)}-${variant}${padded.slice(17, 20)}-${padded.slice(20)}`;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
