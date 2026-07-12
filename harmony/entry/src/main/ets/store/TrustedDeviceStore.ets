import { common } from '@kit.AbilityKit';
import { DeviceConnectionState, DeviceTrustState } from '../models/DomainModels';
import { DeviceRdbRepository, SpaceRdbRepository } from '../data/repositories/RdbRepositories';
import {
  SpaceKeyRecoveryRepository,
  SpaceKeyRecoveryResult,
  SpaceKeyRecoveryService
} from '../services/crypto/SpaceKeyRecoveryService';

export interface TrustedDeviceSummary {
  deviceId: string;
  displayName: string;
  shortFingerprint: string;
  lastSeen: string;
}

export interface TrustedDeviceRenameResult {
  ok: boolean;
  displayName?: string;
  reason?: string;
}

export interface TrustedDeviceRemovalResult {
  ok: boolean;
  recovery?: SpaceKeyRecoveryResult;
  reason?: string;
}

export interface TrustedDeviceReconnectTarget {
  spaceId: string;
  spaceKeyVersion: number;
  deviceId: string;
  identityPublicKey: string;
}

export class TrustedDeviceStore {
  private readonly devices: DeviceRdbRepository;
  private readonly spaces: SpaceRdbRepository;

  constructor(context: common.Context) {
    this.devices = new DeviceRdbRepository(context);
    this.spaces = new SpaceRdbRepository(context);
  }

  async load(): Promise<TrustedDeviceSummary[]> {
    const space = await this.spaces.latestActiveWithKeyRef();
    if (space === null) return [];
    const records = await this.devices.listBySpace(space.space.spaceId);
    return records
      .filter((record) => record.device.trustState === DeviceTrustState.TRUSTED && record.revokedAt === undefined)
      .map((record): TrustedDeviceSummary => ({
        deviceId: record.device.deviceId,
        displayName: record.device.displayName,
        shortFingerprint: shortId(record.device.identityPublicKeyRef),
        lastSeen: record.device.lastSeenAt === undefined ? '尚未在线' : formatTime(record.device.lastSeenAt)
      }));
  }

  async loadFirstReconnectTarget(): Promise<TrustedDeviceReconnectTarget | null> {
    const space = await this.spaces.latestActiveWithKeyRef();
    if (space === null) return null;
    const records = await this.devices.listBySpace(space.space.spaceId);
    const record = records.find((item) => item.device.trustState === DeviceTrustState.TRUSTED &&
      item.revokedAt === undefined && item.device.identityPublicKeyRef.length > 0);
    if (record === undefined) return null;
    return {
      spaceId: space.space.spaceId,
      spaceKeyVersion: space.space.keyVersion,
      deviceId: record.device.deviceId,
      identityPublicKey: record.device.identityPublicKeyRef
    };
  }

  async markRevoked(deviceId: string, revokedAt: number): Promise<void> {
    const record = await this.devices.get(deviceId);
    if (record === null) return;
    record.device.trustState = DeviceTrustState.REVOKED;
    record.device.connectionState = DeviceConnectionState.OFFLINE;
    record.revokedAt = revokedAt;
    await this.devices.upsert(record);
  }

  async rename(deviceId: string, displayName: string): Promise<TrustedDeviceRenameResult> {
    const normalized = normalizeTrustedDeviceName(displayName);
    if (normalized.length === 0) {
      return { ok: false, reason: '设备名称不能为空' };
    }
    const record = await this.devices.get(deviceId);
    if (record === null || record.device.trustState !== DeviceTrustState.TRUSTED ||
      record.revokedAt !== undefined) {
      return { ok: false, reason: '可信设备记录不存在或已撤销' };
    }
    record.device.displayName = normalized;
    await this.devices.upsert(record);
    return { ok: true, displayName: normalized };
  }

  async removeAndClearPairingSecurity(
    deviceId: string,
    revokedAt: number = Date.now()
  ): Promise<TrustedDeviceRemovalResult> {
    const record = await this.devices.get(deviceId);
    if (record === null || record.device.trustState !== DeviceTrustState.TRUSTED ||
      record.revokedAt !== undefined) {
      return { ok: false, reason: '可信设备记录不存在或已撤销' };
    }
    await this.markRevoked(deviceId, revokedAt);
    const recoveryRepository = new TrustedDeviceSpaceRecoveryRepository(this.spaces);
    const recovery = await new SpaceKeyRecoveryService(recoveryRepository).reinitializePairingSecurityState();
    if (!recovery.ok) {
      return { ok: false, recovery, reason: '设备已撤销，但本机旧空间密钥未能完整清理' };
    }
    return { ok: true, recovery };
  }
}

class TrustedDeviceSpaceRecoveryRepository implements SpaceKeyRecoveryRepository {
  private readonly spaces: SpaceRdbRepository;

  constructor(spaces: SpaceRdbRepository) {
    this.spaces = spaces;
  }

  async listEncryptedSpaceKeyRefs(): Promise<string[]> {
    return await this.spaces.listEncryptedSpaceKeyRefs();
  }

  async resetPairingSecurityState(): Promise<void> {
    await this.spaces.resetPairingSecurityState();
  }
}

export function normalizeTrustedDeviceName(value: string): string {
  return value.trim().replace(/\s+/g, ' ').slice(0, 40);
}

function shortId(value: string): string {
  return value.length >= 8 ? value.slice(0, 8) : value;
}

function formatTime(value: number): string {
  const date = new Date(value);
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
