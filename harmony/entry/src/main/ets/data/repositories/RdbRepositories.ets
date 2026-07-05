import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import {
  AppSettings,
  ClipboardItem,
  ClipboardDedupDecision,
  ContentType,
  Device,
  DeviceConnectionState,
  DeviceTrustState,
  Space,
  SpaceState,
  SyncHead,
  defaultAppSettings,
  deduplicateClipboardItem,
  validateAppSettings
} from '../../models/DomainModels';
import { Database } from '../db/Database';
import { RdbCommandRunner } from '../db/RdbCommandRunner';
import {
  ClipboardItemRecord,
  ClipboardRepository,
  DeviceRecord,
  DeviceRepository,
  SettingsRepository,
  SpaceRecord,
  SpaceRepository,
  SyncHeadRecord,
  SyncHeadRepository
} from './RepositoryCommands';

const RECENT_POC_ENDPOINT_KEY: string = 'pocRecentEndpoint';

export interface RecentPocEndpointRecord {
  host: string;
  port: number;
  connectedAt: number;
}

export interface PairingCompletionRecord {
  space: SpaceRecord;
  device: DeviceRecord;
}

export class PairingRdbRepository {
  private readonly context: common.Context;
  private readonly spaceCommands: SpaceRepository = new SpaceRepository();
  private readonly deviceCommands: DeviceRepository = new DeviceRepository();
  private readonly runner: RdbCommandRunner = new RdbCommandRunner();

  constructor(context: common.Context) {
    this.context = context;
  }

  async persistCompletion(record: PairingCompletionRecord): Promise<void> {
    const store = await Database.getStore(this.context);
    let failedStage = 'transaction';
    store.beginTransaction();
    try {
      try {
        await this.runner.execute(store, this.spaceCommands.upsert(record.space));
      } catch (_) {
        failedStage = 'space';
        throw new Error('space');
      }
      try {
        await this.runner.execute(store, this.deviceCommands.upsert(record.device));
      } catch (_) {
        failedStage = 'device';
        throw new Error('device');
      }
      store.commit();
    } catch (_) {
      store.rollBack();
      throw new Error(failedStage);
    }
  }
}

export class SpaceRdbRepository {
  private readonly context: common.Context;
  private readonly commands: SpaceRepository = new SpaceRepository();
  private readonly runner: RdbCommandRunner = new RdbCommandRunner();

  constructor(context: common.Context) {
    this.context = context;
  }

  async upsert(record: SpaceRecord): Promise<void> {
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, this.commands.upsert(record));
  }

  async get(spaceId: string): Promise<SpaceRecord | null> {
    const store = await Database.getStore(this.context);
    const resultSet = await store.querySql(
      `SELECT space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at
        FROM spaces WHERE space_id = ? LIMIT 1`,
      [spaceId]
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return readSpaceRecord(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async latestActiveWithKeyRef(): Promise<SpaceRecord | null> {
    const store = await Database.getStore(this.context);
    const resultSet = await store.querySql(
      `SELECT space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at
        FROM spaces
        WHERE state = ? AND encrypted_space_key_ref IS NOT NULL AND encrypted_space_key_ref <> ''
        ORDER BY updated_at DESC
        LIMIT 1`,
      [SpaceState.ACTIVE]
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return readSpaceRecord(resultSet);
    } finally {
      resultSet.close();
    }
  }
}

export class DeviceRdbRepository {
  private readonly context: common.Context;
  private readonly commands: DeviceRepository = new DeviceRepository();
  private readonly runner: RdbCommandRunner = new RdbCommandRunner();

  constructor(context: common.Context) {
    this.context = context;
  }

  async upsert(record: DeviceRecord): Promise<void> {
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, this.commands.upsert(record));
  }

  async get(deviceId: string): Promise<DeviceRecord | null> {
    const store = await Database.getStore(this.context);
    const resultSet = await store.querySql(
      `SELECT device_id, space_id, display_name, identity_public_key, trust_state,
        connection_state, paired_at, last_seen_at, revoked_at
        FROM devices WHERE device_id = ? LIMIT 1`,
      [deviceId]
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return readDeviceRecord(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async listBySpace(spaceId: string): Promise<DeviceRecord[]> {
    const store = await Database.getStore(this.context);
    const command = this.commands.listBySpace(spaceId);
    const resultSet = await store.querySql(command.sql, this.runner.bindArgs(command.args));
    const records: DeviceRecord[] = [];
    try {
      if (!resultSet.goToFirstRow()) {
        return records;
      }
      do {
        records.push(readDeviceRecord(resultSet));
      } while (resultSet.goToNextRow());
      return records;
    } finally {
      resultSet.close();
    }
  }
}

export class ClipboardRdbRepository {
  private readonly context: common.Context;
  private readonly commands: ClipboardRepository = new ClipboardRepository();
  private readonly runner: RdbCommandRunner = new RdbCommandRunner();

  constructor(context: common.Context) {
    this.context = context;
  }

  async insert(record: ClipboardItemRecord): Promise<void> {
    const command = this.commands.insert(record);
    if (command === null) {
      throw new Error('Invalid clipboard item record');
    }
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, command);
  }

  async insertDeduplicated(record: ClipboardItemRecord): Promise<ClipboardDedupDecision> {
    const existingByItemId = await this.get(record.item.itemId);
    if (existingByItemId !== null) {
      return deduplicateClipboardItem(existingByItemId.item, record.item);
    }

    const existingByOrigin = await this.getByOriginSequence(
      record.item.originDeviceId,
      record.item.originSeq
    );
    if (existingByOrigin !== null) {
      return deduplicateClipboardItem(existingByOrigin.item, record.item);
    }

    await this.insert(record);
    return ClipboardDedupDecision.NEW;
  }

  async get(itemId: string): Promise<ClipboardItemRecord | null> {
    const store = await Database.getStore(this.context);
    const command = this.commands.get(itemId);
    const resultSet = await store.querySql(command.sql, this.runner.bindArgs(command.args));
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return readClipboardRecord(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async listRecent(spaceId: string, limit: number): Promise<ClipboardItemRecord[]> {
    const store = await Database.getStore(this.context);
    const command = this.commands.listRecent(spaceId, limit);
    const resultSet = await store.querySql(command.sql, this.runner.bindArgs(command.args));
    const records: ClipboardItemRecord[] = [];
    try {
      if (!resultSet.goToFirstRow()) {
        return records;
      }
      do {
        records.push(readClipboardRecord(resultSet));
      } while (resultSet.goToNextRow());
      return records;
    } finally {
      resultSet.close();
    }
  }

  async listRecentAll(limit: number): Promise<ClipboardItemRecord[]> {
    const store = await Database.getStore(this.context);
    const command = this.commands.listRecentAll(limit);
    const resultSet = await store.querySql(command.sql, this.runner.bindArgs(command.args));
    const records: ClipboardItemRecord[] = [];
    try {
      if (!resultSet.goToFirstRow()) {
        return records;
      }
      do {
        records.push(readClipboardRecord(resultSet));
      } while (resultSet.goToNextRow());
      return records;
    } finally {
      resultSet.close();
    }
  }

  async countAllActive(): Promise<number> {
    const store = await Database.getStore(this.context);
    const command = this.commands.countAllActive();
    const resultSet = await store.querySql(command.sql, this.runner.bindArgs(command.args));
    try {
      if (!resultSet.goToFirstRow()) {
        return 0;
      }
      return getNumber(resultSet, 'active_count');
    } finally {
      resultSet.close();
    }
  }

  async getByOriginSequence(originDeviceId: string, originSeq: number): Promise<ClipboardItemRecord | null> {
    const store = await Database.getStore(this.context);
    const resultSet = await store.querySql(
      `SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
        content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
        FROM clipboard_items WHERE origin_device_id = ? AND origin_seq = ? LIMIT 1`,
      [originDeviceId, originSeq]
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return readClipboardRecord(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async markDeleted(itemId: string, deletedAt: number): Promise<void> {
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, this.commands.markDeleted(itemId, deletedAt));
  }

  async clearHistory(spaceId: string, deletedAt: number): Promise<void> {
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, this.commands.clearHistory(spaceId, deletedAt));
  }

  async clearAllHistory(deletedAt: number): Promise<void> {
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, this.commands.clearAllHistory(deletedAt));
  }

  async applyRetention(spaceId: string, settings: AppSettings, nowMs: number): Promise<void> {
    const commands = this.commands.retentionCommands(spaceId, settings, nowMs);
    if (commands === null) {
      throw new Error('Invalid app settings for retention');
    }
    const store = await Database.getStore(this.context);
    await this.runner.executeTransaction(store, commands);
  }

  async applyRetentionAll(settings: AppSettings, nowMs: number): Promise<void> {
    const commands = this.commands.retentionAllCommands(settings, nowMs);
    if (commands === null) {
      throw new Error('Invalid app settings for retention');
    }
    const store = await Database.getStore(this.context);
    await this.runner.executeTransaction(store, commands);
  }
}

export class SyncHeadRdbRepository {
  private readonly context: common.Context;
  private readonly commands: SyncHeadRepository = new SyncHeadRepository();
  private readonly runner: RdbCommandRunner = new RdbCommandRunner();

  constructor(context: common.Context) {
    this.context = context;
  }

  async upsert(record: SyncHeadRecord): Promise<void> {
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, this.commands.upsert(record));
  }

  async listForPeer(spaceId: string, peerDeviceId: string): Promise<SyncHeadRecord[]> {
    const store = await Database.getStore(this.context);
    const resultSet = await store.querySql(
      `SELECT space_id, peer_device_id, origin_device_id, highest_origin_seq, minimum_available, updated_at
        FROM sync_heads WHERE space_id = ? AND peer_device_id = ?
        ORDER BY origin_device_id`,
      [spaceId, peerDeviceId]
    );
    const records: SyncHeadRecord[] = [];
    try {
      if (!resultSet.goToFirstRow()) {
        return records;
      }
      do {
        records.push(readSyncHeadRecord(resultSet));
      } while (resultSet.goToNextRow());
      return records;
    } finally {
      resultSet.close();
    }
  }
}

export class SettingsRdbRepository {
  private readonly context: common.Context;
  private readonly commands: SettingsRepository = new SettingsRepository();
  private readonly runner: RdbCommandRunner = new RdbCommandRunner();

  constructor(context: common.Context) {
    this.context = context;
  }

  async saveAppSettings(settings: AppSettings, updatedAt: number): Promise<void> {
    const command = this.commands.saveAppSettings(settings, updatedAt);
    if (command === null) {
      throw new Error('Invalid app settings');
    }
    const store = await Database.getStore(this.context);
    await this.runner.execute(store, command);
  }

  async loadAppSettings(): Promise<AppSettings | null> {
    const store = await Database.getStore(this.context);
    const command = this.commands.loadAppSettings();
    const resultSet = await store.querySql(command.sql, this.runner.bindArgs(command.args));
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      const value = getString(resultSet, 'value');
      const parsed = JSON.parse(value) as AppSettings;
      const defaults = defaultAppSettings();
      const settings: AppSettings = {
        syncEnabled: parsed.syncEnabled ?? defaults.syncEnabled,
        autoReceiveEnabled: parsed.autoReceiveEnabled ?? defaults.autoReceiveEnabled,
        autoWriteEnabled: parsed.autoWriteEnabled ?? defaults.autoWriteEnabled,
        historyEnabled: parsed.historyEnabled ?? defaults.historyEnabled,
        historyLimit: parsed.historyLimit ?? defaults.historyLimit,
        retentionDays: parsed.retentionDays ?? defaults.retentionDays,
        themeMode: parsed.themeMode ?? defaults.themeMode
      };
      if (!validateAppSettings(settings).ok) {
        throw new Error('Invalid app settings metadata');
      }
      return settings;
    } finally {
      resultSet.close();
    }
  }

  async saveRecentPocEndpoint(record: RecentPocEndpointRecord): Promise<void> {
    if (!isValidRecentPocEndpoint(record)) {
      throw new Error('Invalid recent POC endpoint');
    }
    const store = await Database.getStore(this.context);
    await store.executeSql(
      `INSERT INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      this.runner.bindArgs([RECENT_POC_ENDPOINT_KEY, JSON.stringify(record), record.connectedAt])
    );
  }

  async loadRecentPocEndpoint(): Promise<RecentPocEndpointRecord | null> {
    const store = await Database.getStore(this.context);
    const resultSet = await store.querySql(
      'SELECT value FROM app_metadata WHERE key = ? LIMIT 1',
      this.runner.bindArgs([RECENT_POC_ENDPOINT_KEY])
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      const parsed = JSON.parse(getString(resultSet, 'value')) as RecentPocEndpointRecord;
      if (!isValidRecentPocEndpoint(parsed)) {
        return null;
      }
      return parsed;
    } finally {
      resultSet.close();
    }
  }
}

function readSpaceRecord(resultSet: relationalStore.ResultSet): SpaceRecord {
  const encryptedSpaceKeyRef = getNullableString(resultSet, 'encrypted_space_key_ref');
  const space: Space = {
    spaceId: getString(resultSet, 'space_id'),
    displayName: getString(resultSet, 'display_name'),
    keyVersion: getNumber(resultSet, 'key_version'),
    state: getString(resultSet, 'state') as SpaceState,
    createdAt: getNumber(resultSet, 'created_at')
  };
  return {
    space,
    encryptedSpaceKeyRef: encryptedSpaceKeyRef ?? undefined,
    updatedAt: getNumber(resultSet, 'updated_at')
  };
}

function readDeviceRecord(resultSet: relationalStore.ResultSet): DeviceRecord {
  const lastSeenAt = getNullableNumber(resultSet, 'last_seen_at');
  const device: Device = {
    deviceId: getString(resultSet, 'device_id'),
    spaceId: getString(resultSet, 'space_id'),
    displayName: getString(resultSet, 'display_name'),
    identityPublicKeyRef: getString(resultSet, 'identity_public_key'),
    trustState: getString(resultSet, 'trust_state') as DeviceTrustState,
    connectionState: getString(resultSet, 'connection_state') as DeviceConnectionState,
    lastSeenAt: lastSeenAt ?? undefined
  };
  return {
    device,
    pairedAt: getNullableNumber(resultSet, 'paired_at') ?? undefined,
    revokedAt: getNullableNumber(resultSet, 'revoked_at') ?? undefined
  };
}

function readClipboardRecord(resultSet: relationalStore.ResultSet): ClipboardItemRecord {
  const item: ClipboardItem = {
    itemId: getString(resultSet, 'item_id'),
    spaceId: getString(resultSet, 'space_id'),
    originDeviceId: getString(resultSet, 'origin_device_id'),
    originSeq: getNumber(resultSet, 'origin_seq'),
    hlc: getString(resultSet, 'hlc'),
    contentType: getString(resultSet, 'content_type') as ContentType,
    contentLength: getNumber(resultSet, 'content_length'),
    contentDigest: getString(resultSet, 'content_digest'),
    createdAt: getNumber(resultSet, 'created_at')
  };
  return {
    item,
    encryptedContent: getBlob(resultSet, 'encrypted_content'),
    receivedAt: getNumber(resultSet, 'received_at'),
    expiresAt: getNumber(resultSet, 'expires_at'),
    deletedAt: getNullableNumber(resultSet, 'deleted_at') ?? undefined
  };
}

function readSyncHeadRecord(resultSet: relationalStore.ResultSet): SyncHeadRecord {
  const head: SyncHead = {
    spaceId: getString(resultSet, 'space_id'),
    originDeviceId: getString(resultSet, 'origin_device_id'),
    latestOriginSeq: getNumber(resultSet, 'highest_origin_seq'),
    minimumAvailable: getNumber(resultSet, 'minimum_available'),
    updatedAt: getNumber(resultSet, 'updated_at')
  };
  return {
    head,
    peerDeviceId: getString(resultSet, 'peer_device_id')
  };
}

function getString(resultSet: relationalStore.ResultSet, columnName: string): string {
  return resultSet.getString(resultSet.getColumnIndex(columnName));
}

function getNullableString(resultSet: relationalStore.ResultSet, columnName: string): string | null {
  const columnIndex = resultSet.getColumnIndex(columnName);
  if (resultSet.isColumnNull(columnIndex)) {
    return null;
  }
  return resultSet.getString(columnIndex);
}

function getNumber(resultSet: relationalStore.ResultSet, columnName: string): number {
  return resultSet.getLong(resultSet.getColumnIndex(columnName));
}

function getNullableNumber(resultSet: relationalStore.ResultSet, columnName: string): number | null {
  const columnIndex = resultSet.getColumnIndex(columnName);
  if (resultSet.isColumnNull(columnIndex)) {
    return null;
  }
  return resultSet.getLong(columnIndex);
}

function getBlob(resultSet: relationalStore.ResultSet, columnName: string): Uint8Array {
  const columnIndex = resultSet.getColumnIndex(columnName);
  if (resultSet.isColumnNull(columnIndex)) {
    return new Uint8Array();
  }
  return resultSet.getBlob(columnIndex);
}

function isValidRecentPocEndpoint(record: RecentPocEndpointRecord): boolean {
  if (!isValidIpv4Host(record.host)) {
    return false;
  }
  if (!Number.isInteger(record.port) || record.port < 1 || record.port > 65535) {
    return false;
  }
  return Number.isSafeInteger(record.connectedAt) && record.connectedAt >= 0;
}

function isValidIpv4Host(host: string): boolean {
  const parts = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index];
    if (part.length === 0 || !/^[0-9]+$/.test(part)) {
      return false;
    }
    const value = Number(part);
    if (!Number.isInteger(value) || value < 0 || value > 255) {
      return false;
    }
    if (index === 0 && value >= 224 && value <= 239) {
      return false;
    }
  }
  return host !== '0.0.0.0' && host !== '255.255.255.255';
}
