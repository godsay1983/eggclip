import {
  AppSettings,
  ClipboardItem,
  Device,
  Space,
  SyncHead,
  validateAppSettings,
  validateClipboardItemFields
} from '../../models/DomainModels';

export type SqlValue = string | number | Uint8Array | null;

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

  markExpired(spaceId: string, nowMs: number): RepositoryCommand {
    return {
      sql: `UPDATE clipboard_items SET deleted_at = ?
        WHERE space_id = ? AND deleted_at IS NULL AND expires_at <= ?`,
      args: [nowMs, spaceId, nowMs]
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
