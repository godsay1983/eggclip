import { common } from '@kit.AbilityKit';
import { DeviceTrustState } from '../models/DomainModels';
import { DeviceRdbRepository, SpaceRdbRepository } from '../data/repositories/RdbRepositories';

export interface TrustedDeviceSummary {
  deviceId: string;
  displayName: string;
  shortFingerprint: string;
  lastSeen: string;
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
      .filter((record) => record.device.trustState === DeviceTrustState.TRUSTED)
      .map((record): TrustedDeviceSummary => ({
        deviceId: record.device.deviceId,
        displayName: record.device.displayName,
        shortFingerprint: shortId(record.device.identityPublicKeyRef),
        lastSeen: record.device.lastSeenAt === undefined ? '尚未在线' : formatTime(record.device.lastSeenAt)
      }));
  }
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
