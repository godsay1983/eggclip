import {
  AppSettings,
  ClipboardItem,
  Device,
  HlcTimestamp,
  Space,
  SyncHead,
  buildLocalClipboardItemDraft,
  validateAppSettings,
  validateClipboardItemFields
} from '../../models/DomainModels';

export type SqlValue = string | number | Uint8Array | null;
export const LOCAL_DEVICE_ID_KEY: string = 'localDeviceId';
export const LOCAL_IDENTITY_PUBLIC_KEY_KEY: string = 'localIdentityPublicKey';
export const LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY: string = 'localIdentityPrivateKeyRef';
export const NEXT_ORIGIN_SEQ_KEY: string = 'nextOriginSeq';
export const INITIAL_ORIGIN_SEQ: number = 1;

export interface RepositoryCommand {
  sql: string;
  args: SqlValue[];
}

export interface ClipboardItemRecord {
  item: ClipboardItem;
  encryptedContent: Uint8Array;
  receivedAt: number;
  expiresAt: number;
  deletedAt?: number;
}

export interface SpaceRecord {
  space: Space;
  encryptedSpaceKeyRef?: string;
  updatedAt: number;
}

export interface DeviceRecord {
  device: Device;
  pairedAt?: number;
  revokedAt?: number;
}

export interface SyncHeadRecord {
  head: SyncHead;
  peerDeviceId: string;
}

export interface LocalClipboardPersistCommandInput {
  itemId: string;
  spaceId: string;
  originDeviceId: string;
  originSeq: number;
  text: string;
  contentDigest: string;
  encryptedContent: Uint8Array;
  settings: AppSettings;
  nowMs: number;
}

export interface LocalClipboardPersistCommandPlan {
  record: ClipboardItemRecord;
  commands: RepositoryCommand[];
}

export class ClipboardRepository {
  insert(record: ClipboardItemRecord): RepositoryCommand | null {
    if (!validateClipboardItemFields(record.item).ok) {
      return null;
    }
    return {
      sql: `INSERT OR IGNORE INTO clipboard_items(
        item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
        content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      args: [
        record.item.itemId,
        record.item.spaceId,
        record.item.originDeviceId,
        record.item.originSeq,
        record.item.hlc,
        record.item.contentType,
        record.item.contentLength,
        record.item.contentDigest,
        record.encryptedContent,
        record.item.createdAt,
        record.receivedAt,
        record.expiresAt,
        record.deletedAt ?? null
      ]
    };
  }

  get(itemId: string): RepositoryCommand {
    return {
      sql: `SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
        content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
        FROM clipboard_items WHERE item_id = ?`,
      args: [itemId]
    };
  }

  listRecent(spaceId: string, limit: number): RepositoryCommand {
    return {
      sql: `SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
        content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
        FROM clipboard_items
        WHERE space_id = ? AND deleted_at IS NULL
        ORDER BY hlc DESC, item_id DESC
        LIMIT ?`,
      args: [spaceId, limit]
    };
  }

  listRecentAll(limit: number): RepositoryCommand {
    return {
      sql: `SELECT item_id, space_id, origin_device_id, origin_seq, hlc, content_type,
        content_length, content_digest, encrypted_content, created_at, received_at, expires_at, deleted_at
        FROM clipboard_items
        WHERE deleted_at IS NULL
        ORDER BY hlc DESC, item_id DESC
        LIMIT ?`,
      args: [limit]
    };
  }

  countAllActive(): RepositoryCommand {
    return {
      sql: 'SELECT COUNT(*) AS active_count FROM clipboard_items WHERE deleted_at IS NULL',
      args: []
    };
  }

  markDeleted(itemId: string, deletedAt: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE item_id = ? AND deleted_at IS NULL`,
      args: [deletedAt, itemId]
    };
  }

  clearHistory(spaceId: string, deletedAt: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE space_id = ? AND deleted_at IS NULL`,
      args: [deletedAt, spaceId]
    };
  }

  clearAllHistory(deletedAt: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE deleted_at IS NULL`,
      args: [deletedAt]
    };
  }

  markExpired(spaceId: string, nowMs: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE space_id = ? AND deleted_at IS NULL AND expires_at <= ?`,
      args: [nowMs, spaceId, nowMs]
    };
  }

  markExpiredAll(nowMs: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE deleted_at IS NULL AND expires_at <= ?`,
      args: [nowMs, nowMs]
    };
  }

  markOverflow(spaceId: string, historyLimit: number, deletedAt: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE space_id = ? AND deleted_at IS NULL AND item_id IN (
          SELECT item_id FROM clipboard_items
          WHERE space_id = ? AND deleted_at IS NULL
          ORDER BY hlc DESC, item_id DESC
          LIMIT -1 OFFSET ?
        )`,
      args: [deletedAt, spaceId, spaceId, historyLimit]
    };
  }

  markOverflowAll(historyLimit: number, deletedAt: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE deleted_at IS NULL AND item_id IN (
          SELECT item_id FROM clipboard_items
          WHERE deleted_at IS NULL
          ORDER BY hlc DESC, item_id DESC
          LIMIT -1 OFFSET ?
        )`,
      args: [deletedAt, historyLimit]
    };
  }

  retentionCommands(spaceId: string, settings: AppSettings, nowMs: number): RepositoryCommand[] | null {
    if (!validateAppSettings(settings).ok) {
      return null;
    }
    if (!settings.historyEnabled || settings.historyLimit === 0) {
      return [this.clearHistory(spaceId, nowMs)];
    }
    return [
      this.markExpired(spaceId, nowMs),
      this.markOverflow(spaceId, settings.historyLimit, nowMs)
    ];
  }

  retentionAllCommands(settings: AppSettings, nowMs: number): RepositoryCommand[] | null {
    if (!validateAppSettings(settings).ok) {
      return null;
    }
    if (!settings.historyEnabled || settings.historyLimit === 0) {
      return [this.clearAllHistory(nowMs)];
    }
    return [
      this.markExpiredAll(nowMs),
      this.markOverflowAll(settings.historyLimit, nowMs)
    ];
  }
}

const MILLIS_PER_DAY: number = 24 * 60 * 60 * 1000;

export class LocalClipboardPersistenceCommands {
  build(input: LocalClipboardPersistCommandInput): LocalClipboardPersistCommandPlan | null {
    if (!validateAppSettings(input.settings).ok) {
      return null;
    }
    if (!Number.isSafeInteger(input.nowMs + input.settings.retentionDays * MILLIS_PER_DAY)) {
      return null;
    }

    const item = buildLocalClipboardItemDraft({
      itemId: input.itemId,
      spaceId: input.spaceId,
      originDeviceId: input.originDeviceId,
      originSeq: input.originSeq,
      hlc: new HlcTimestamp(input.nowMs, 0),
      createdAt: input.nowMs,
      contentDigest: input.contentDigest
    }, input.text);
    if (!item.ok || item.item === undefined) {
      return null;
    }

    const identity = new LocalIdentityRepository();
    const clipboard = new ClipboardRepository();
    const record: ClipboardItemRecord = {
      item: item.item,
      encryptedContent: input.encryptedContent,
      receivedAt: input.nowMs,
      expiresAt: input.nowMs + input.settings.retentionDays * MILLIS_PER_DAY
    };
    const advance = identity.advanceOriginSeq(input.originSeq, input.nowMs);
    const insert = clipboard.insert(record);
    if (advance === null || insert === null) {
      return null;
    }

    return {
      record,
      commands: [
        identity.initializeOriginSeq(input.nowMs),
        advance,
        insert
      ]
    };
  }
}

export class SpaceRepository {
  upsert(record: SpaceRecord): RepositoryCommand {
    return {
      sql: `INSERT INTO spaces(
        space_id, display_name, encrypted_space_key_ref, key_version, state, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(space_id) DO UPDATE SET
        display_name = excluded.display_name,
        encrypted_space_key_ref = excluded.encrypted_space_key_ref,
        key_version = excluded.key_version,
        state = excluded.state,
        updated_at = excluded.updated_at`,
      args: [
        record.space.spaceId,
        record.space.displayName,
        record.encryptedSpaceKeyRef ?? null,
        record.space.keyVersion,
        record.space.state,
        record.space.createdAt,
        record.updatedAt
      ]
    };
  }
}

export class DeviceRepository {
  upsert(record: DeviceRecord): RepositoryCommand {
    return {
      sql: `INSERT INTO devices(
        device_id, space_id, display_name, identity_public_key, trust_state,
        connection_state, paired_at, last_seen_at, revoked_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        display_name = excluded.display_name,
        identity_public_key = excluded.identity_public_key,
        trust_state = excluded.trust_state,
        connection_state = excluded.connection_state,
        last_seen_at = excluded.last_seen_at,
        revoked_at = excluded.revoked_at`,
      args: [
        record.device.deviceId,
        record.device.spaceId,
        record.device.displayName,
        record.device.identityPublicKeyRef,
        record.device.trustState,
        record.device.connectionState,
        record.pairedAt ?? null,
        record.device.lastSeenAt ?? null,
        record.revokedAt ?? null
      ]
    };
  }

  listBySpace(spaceId: string): RepositoryCommand {
    return {
      sql: `SELECT device_id, space_id, display_name, identity_public_key, trust_state,
        connection_state, paired_at, last_seen_at, revoked_at
        FROM devices WHERE space_id = ? ORDER BY display_name, device_id`,
      args: [spaceId]
    };
  }
}

export class SyncHeadRepository {
  upsert(record: SyncHeadRecord): RepositoryCommand {
    return {
      sql: `INSERT INTO sync_heads(
        space_id, peer_device_id, origin_device_id, highest_origin_seq, minimum_available, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(space_id, peer_device_id, origin_device_id) DO UPDATE SET
        highest_origin_seq = excluded.highest_origin_seq,
        minimum_available = excluded.minimum_available,
        updated_at = excluded.updated_at`,
      args: [
        record.head.spaceId,
        record.peerDeviceId,
        record.head.originDeviceId,
        record.head.latestOriginSeq,
        record.head.minimumAvailable,
        record.head.updatedAt
      ]
    };
  }
}

export class SettingsRepository {
  saveAppSettings(settings: AppSettings, updatedAt: number): RepositoryCommand | null {
    if (!validateAppSettings(settings).ok) {
      return null;
    }
    return {
      sql: `INSERT INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      args: ['appSettings', JSON.stringify(settings), updatedAt]
    };
  }

  loadAppSettings(): RepositoryCommand {
    return {
      sql: 'SELECT value FROM app_metadata WHERE key = ?',
      args: ['appSettings']
    };
  }
}

export class LocalIdentityRepository {
  loadLocalDeviceId(): RepositoryCommand {
    return {
      sql: 'SELECT value FROM app_metadata WHERE key = ?',
      args: [LOCAL_DEVICE_ID_KEY]
    };
  }

  insertLocalDeviceId(deviceId: string, updatedAt: number): RepositoryCommand {
    return {
      sql: 'INSERT OR IGNORE INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)',
      args: [LOCAL_DEVICE_ID_KEY, deviceId, updatedAt]
    };
  }

  loadLocalIdentityPublicKey(): RepositoryCommand {
    return {
      sql: 'SELECT value FROM app_metadata WHERE key = ?',
      args: [LOCAL_IDENTITY_PUBLIC_KEY_KEY]
    };
  }

  saveLocalIdentityPublicKey(identityPublicKey: string, updatedAt: number): RepositoryCommand | null {
    if (!isValidLocalIdentityPublicKey(identityPublicKey)) {
      return null;
    }
    return this.upsertMetadata(LOCAL_IDENTITY_PUBLIC_KEY_KEY, identityPublicKey, updatedAt);
  }

  loadLocalIdentityPrivateKeyRef(): RepositoryCommand {
    return {
      sql: 'SELECT value FROM app_metadata WHERE key = ?',
      args: [LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY]
    };
  }

  saveLocalIdentityPrivateKeyRef(identityPrivateKeyRef: string, updatedAt: number): RepositoryCommand | null {
    if (!isValidLocalIdentityPrivateKeyRef(identityPrivateKeyRef)) {
      return null;
    }
    return this.upsertMetadata(LOCAL_IDENTITY_PRIVATE_KEY_REF_KEY, identityPrivateKeyRef, updatedAt);
  }

  loadNextOriginSeq(): RepositoryCommand {
    return {
      sql: 'SELECT value FROM app_metadata WHERE key = ?',
      args: [NEXT_ORIGIN_SEQ_KEY]
    };
  }

  initializeOriginSeq(updatedAt: number): RepositoryCommand {
    return {
      sql: 'INSERT OR IGNORE INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)',
      args: [NEXT_ORIGIN_SEQ_KEY, INITIAL_ORIGIN_SEQ.toString(), updatedAt]
    };
  }

  advanceOriginSeq(currentSeq: number, updatedAt: number): RepositoryCommand | null {
    if (!Number.isSafeInteger(currentSeq) || currentSeq < 0 || !Number.isSafeInteger(currentSeq + 1)) {
      return null;
    }
    return {
      sql: `UPDATE app_metadata SET value = ?, updated_at = ?
        WHERE key = ? AND value = ?`,
      args: [(currentSeq + 1).toString(), updatedAt, NEXT_ORIGIN_SEQ_KEY, currentSeq.toString()]
    };
  }

  private upsertMetadata(key: string, value: string, updatedAt: number): RepositoryCommand {
    return {
      sql: `INSERT INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      args: [key, value, updatedAt]
    };
  }
}

export function isValidLocalIdentityPublicKey(value: string): boolean {
  return /^[A-Za-z0-9_-]{43}$/.test(value);
}

export function isValidLocalIdentityPrivateKeyRef(value: string): boolean {
  return /^huks:\/\/eggclip\/local-identity\/ed25519\/[A-Za-z0-9._-]{1,64}$/.test(value);
}
