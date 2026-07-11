import cryptoFramework from '@ohos.security.cryptoFramework';
import { common } from '@kit.AbilityKit';
import {
  AppSettings,
  ClipboardDedupDecision,
  DeviceTrustState,
  InboundClipboardEventKind,
  SpaceState,
  defaultAppSettings,
  inboundClipboardPolicy
} from '../../models/DomainModels';
import { JsonObject, ProtocolParser } from '../../models/ProtocolModels';
import {
  ClipboardRdbRepository,
  DeviceRdbRepository,
  SettingsRdbRepository,
  SpaceRdbRepository
} from '../../data/repositories/RdbRepositories';
import { ClipboardItemRecord, DeviceRecord, SpaceRecord } from '../../data/repositories/RepositoryCommands';
import { encodeBase64Url } from '../crypto/CryptoVectorService';
import {
  SpaceKeyAesGcmGateway
} from '../crypto/SpaceKeyCryptoSelfTestService';
import { SpaceKeyHuksService } from '../crypto/SpaceKeyHuksService';

const LOCAL_STORAGE_ENVELOPE_VERSION: number = 1;
const AES_GCM_NONCE_BYTES: number = 12;
const MILLIS_PER_DAY: number = 24 * 60 * 60 * 1000;

export enum InboundItemLiveStatus {
  STORED = 'stored',
  DUPLICATE = 'duplicate',
  IGNORED_BY_POLICY = 'ignoredByPolicy',
  REJECTED = 'rejected',
  FAILED = 'failed'
}

export interface InboundItemLiveInput {
  payload: JsonObject;
  expectedSpaceId: string;
  expectedPeerDeviceId: string;
  eventKind?: InboundClipboardEventKind;
  nowMs: number;
}

export interface InboundItemLiveResult {
  status: InboundItemLiveStatus;
  field?: string;
}

export interface InboundItemLiveStorageGateway {
  loadSettings(): Promise<AppSettings>;
  loadSpace(spaceId: string): Promise<SpaceRecord | null>;
  loadDevice(deviceId: string): Promise<DeviceRecord | null>;
  insertDeduplicated(record: ClipboardItemRecord): Promise<ClipboardDedupDecision>;
  applyRetention(spaceId: string, settings: AppSettings, nowMs: number): Promise<void>;
}

export interface SecureRandomGateway {
  randomBytes(length: number): Promise<Uint8Array>;
}

/**
 * Accepts an already transport-decrypted ITEM_LIVE payload. Transport session keys
 * protect the wire; the space key only protects the local RDB content envelope.
 */
export class InboundItemLiveService {
  private readonly storage: InboundItemLiveStorageGateway;
  private readonly crypto: SpaceKeyAesGcmGateway;
  private readonly random: SecureRandomGateway;
  private readonly parser: ProtocolParser = new ProtocolParser();

  constructor(
    storage: InboundItemLiveStorageGateway,
    crypto: SpaceKeyAesGcmGateway = new SpaceKeyHuksService(),
    random: SecureRandomGateway = new CryptoFrameworkRandomGateway()
  ) {
    this.storage = storage;
    this.crypto = crypto;
    this.random = random;
  }

  async accept(input: InboundItemLiveInput): Promise<InboundItemLiveResult> {
    const parsed = this.parser.parseClipboardItem(JSON.stringify(input.payload));
    if (!parsed.ok || parsed.item === undefined) {
      return rejected(parsed.field ?? 'payload');
    }
    const item = parsed.item;
    if (item.spaceId !== input.expectedSpaceId) {
      return rejected('spaceId');
    }
    const eventKind = input.eventKind ?? InboundClipboardEventKind.ITEM_LIVE;
    if (eventKind === InboundClipboardEventKind.ITEM_LIVE &&
      item.originDeviceId !== input.expectedPeerDeviceId) {
      return rejected('originDeviceId');
    }

    let settings: AppSettings;
    let space: SpaceRecord | null;
    let device: DeviceRecord | null;
    try {
      settings = await this.storage.loadSettings();
      space = await this.storage.loadSpace(item.spaceId);
      device = await this.storage.loadDevice(item.originDeviceId);
    } catch (_) {
      return failed('loadTrustedState');
    }
    if (space === null || !isActiveSpaceWithKey(space, item.spaceId)) {
      return rejected('space');
    }
    if (!isTrustedDeviceForSpace(device, item.originDeviceId, item.spaceId)) {
      return rejected('device');
    }

    const policy = inboundClipboardPolicy(eventKind, settings);
    if (!policy.updateHistory) {
      return { status: InboundItemLiveStatus.IGNORED_BY_POLICY };
    }

    const encryptedContent = await this.encryptForLocalStorage(
      space.encryptedSpaceKeyRef ?? '',
      item.itemId,
      item.spaceId,
      item.originDeviceId,
      item.originSeq,
      item.contentLength,
      item.contentDigest,
      item.content
    );
    if (encryptedContent === null) {
      return failed('encryptLocalContent');
    }

    const record: ClipboardItemRecord = {
      item: {
        itemId: item.itemId,
        spaceId: item.spaceId,
        originDeviceId: item.originDeviceId,
        originSeq: item.originSeq,
        hlc: item.hlc,
        contentType: item.contentType,
        contentLength: item.contentLength,
        contentDigest: item.contentDigest,
        createdAt: item.createdAt
      },
      encryptedContent,
      receivedAt: input.nowMs,
      expiresAt: input.nowMs + settings.retentionDays * MILLIS_PER_DAY
    };
    try {
      const decision = await this.storage.insertDeduplicated(record);
      if (decision === ClipboardDedupDecision.CONFLICT) {
        return rejected('dedupConflict');
      }
      if (decision === ClipboardDedupDecision.DUPLICATE) {
        return { status: InboundItemLiveStatus.DUPLICATE };
      }
      await this.storage.applyRetention(item.spaceId, settings, input.nowMs);
      return { status: InboundItemLiveStatus.STORED };
    } catch (_) {
      return failed('persist');
    }
  }

  private async encryptForLocalStorage(
    encryptedSpaceKeyRef: string,
    itemId: string,
    spaceId: string,
    originDeviceId: string,
    originSeq: number,
    contentLength: number,
    contentDigest: string,
    content: string
  ): Promise<Uint8Array | null> {
    let nonce: Uint8Array;
    try {
      nonce = await this.random.randomBytes(AES_GCM_NONCE_BYTES);
    } catch (_) {
      return null;
    }
    if (nonce.length !== AES_GCM_NONCE_BYTES) {
      return null;
    }
    const nonceBase64Url = encodeBase64Url(nonce);
    const aadBase64Url = encodeBase64Url(utf8Encode(localStorageAad(
      itemId,
      spaceId,
      originDeviceId,
      originSeq,
      contentLength,
      contentDigest
    )));
    const plaintextBase64Url = encodeBase64Url(utf8Encode(content));
    const encrypted = await this.crypto.encryptBase64Url(
      encryptedSpaceKeyRef,
      nonceBase64Url,
      aadBase64Url,
      plaintextBase64Url
    );
    if (!encrypted.ok || encrypted.body === undefined || encrypted.tag === undefined) {
      return null;
    }
    return utf8Encode(JSON.stringify({
      version: LOCAL_STORAGE_ENVELOPE_VERSION,
      nonce: nonceBase64Url,
      aad: aadBase64Url,
      body: encrypted.body,
      tag: encrypted.tag
    }));
  }
}

export class RdbInboundItemLiveStorageGateway implements InboundItemLiveStorageGateway {
  private readonly settings: SettingsRdbRepository;
  private readonly spaces: SpaceRdbRepository;
  private readonly devices: DeviceRdbRepository;
  private readonly clipboard: ClipboardRdbRepository;

  constructor(context: common.Context) {
    this.settings = new SettingsRdbRepository(context);
    this.spaces = new SpaceRdbRepository(context);
    this.devices = new DeviceRdbRepository(context);
    this.clipboard = new ClipboardRdbRepository(context);
  }

  async loadSettings(): Promise<AppSettings> {
    return await this.settings.loadAppSettings() ?? defaultAppSettings();
  }

  async loadSpace(spaceId: string): Promise<SpaceRecord | null> {
    return await this.spaces.get(spaceId);
  }

  async loadDevice(deviceId: string): Promise<DeviceRecord | null> {
    return await this.devices.get(deviceId);
  }

  async insertDeduplicated(record: ClipboardItemRecord): Promise<ClipboardDedupDecision> {
    return await this.clipboard.insertDeduplicated(record);
  }

  async applyRetention(spaceId: string, settings: AppSettings, nowMs: number): Promise<void> {
    await this.clipboard.applyRetention(spaceId, settings, nowMs);
  }
}

export class CryptoFrameworkRandomGateway implements SecureRandomGateway {
  async randomBytes(length: number): Promise<Uint8Array> {
    const result = await cryptoFramework.createRandom().generateRandom(length);
    return result.data;
  }
}

function isActiveSpaceWithKey(space: SpaceRecord | null, spaceId: string): boolean {
  return space !== null && space.space.spaceId === spaceId &&
    space.space.state === SpaceState.ACTIVE &&
    space.encryptedSpaceKeyRef !== undefined && space.encryptedSpaceKeyRef.length > 0;
}

function isTrustedDeviceForSpace(device: DeviceRecord | null, deviceId: string, spaceId: string): boolean {
  return device !== null && device.device.deviceId === deviceId &&
    device.device.spaceId === spaceId && device.device.trustState === DeviceTrustState.TRUSTED;
}

function localStorageAad(
  itemId: string,
  spaceId: string,
  originDeviceId: string,
  originSeq: number,
  contentLength: number,
  contentDigest: string
): string {
  return 'EggClip v1 local clipboard storage\n' +
    `itemId=${itemId}\n` +
    `spaceId=${spaceId}\n` +
    `originDeviceId=${originDeviceId}\n` +
    `originSeq=${originSeq}\n` +
    `contentLength=${contentLength}\n` +
    `contentDigest=${contentDigest}\n`;
}

function utf8Encode(value: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) {
      bytes.push(code);
    } else if (code <= 0x7ff) {
      bytes.push(0xc0 | (code >> 6));
      bytes.push(0x80 | (code & 0x3f));
    } else {
      bytes.push(0xe0 | (code >> 12));
      bytes.push(0x80 | ((code >> 6) & 0x3f));
      bytes.push(0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(bytes);
}

function rejected(field: string): InboundItemLiveResult {
  return { status: InboundItemLiveStatus.REJECTED, field };
}

function failed(field: string): InboundItemLiveResult {
  return { status: InboundItemLiveStatus.FAILED, field };
}
