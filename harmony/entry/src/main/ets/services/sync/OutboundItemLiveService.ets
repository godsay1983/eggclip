import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ContentType, SpaceState, defaultAppSettings } from '../../models/DomainModels';
import { JsonObject } from '../../models/ProtocolModels';
import {
  ClipboardRdbRepository,
  SettingsRdbRepository,
  SpaceRdbRepository
} from '../../data/repositories/RdbRepositories';
import { LocalIdentityRdbRepository } from '../../data/repositories/LocalIdentityRdbRepository';
import { encodeBase64Url } from '../crypto/CryptoVectorService';
import { SpaceKeyHuksService } from '../crypto/SpaceKeyHuksService';
import { CryptoFrameworkRandomGateway } from './InboundItemLiveService';
import { LocalClipboardPersistenceService } from './LocalClipboardPersistenceService';

const NONCE_BYTES: number = 12;

export enum OutboundItemLiveStatus {
  READY = 'ready',
  PAUSED = 'paused',
  REJECTED = 'rejected',
  FAILED = 'failed'
}

export interface OutboundItemLiveResult {
  status: OutboundItemLiveStatus;
  payload?: JsonObject;
  field?: string;
}

/** Builds and commits a local item before its authenticated transport send. */
export class OutboundItemLiveService {
  private readonly settings: SettingsRdbRepository;
  private readonly spaces: SpaceRdbRepository;
  private readonly identity: LocalIdentityRdbRepository;
  private readonly clipboard: ClipboardRdbRepository;
  private readonly persistence: LocalClipboardPersistenceService;
  private readonly huks: SpaceKeyHuksService;
  private readonly random: CryptoFrameworkRandomGateway = new CryptoFrameworkRandomGateway();

  constructor(context: common.Context, huks: SpaceKeyHuksService = new SpaceKeyHuksService()) {
    this.settings = new SettingsRdbRepository(context);
    this.spaces = new SpaceRdbRepository(context);
    this.identity = new LocalIdentityRdbRepository(context);
    this.clipboard = new ClipboardRdbRepository(context);
    this.persistence = new LocalClipboardPersistenceService(context);
    this.huks = huks;
  }

  async persist(spaceId: string, text: string, nowMs: number): Promise<OutboundItemLiveResult> {
    try {
      const settings = await this.settings.loadAppSettings() ?? defaultAppSettings();
      if (!settings.syncEnabled) {
        return { status: OutboundItemLiveStatus.PAUSED, field: 'syncEnabled' };
      }
      const space = await this.spaces.get(spaceId);
      if (space === null || space.space.state !== SpaceState.ACTIVE ||
        space.encryptedSpaceKeyRef === undefined || space.encryptedSpaceKeyRef.length === 0) {
        return { status: OutboundItemLiveStatus.REJECTED, field: 'space' };
      }
      const digest = await this.huks.hmacSha256Base64Url(
        space.encryptedSpaceKeyRef,
        encodeBase64Url(utf8Encode(`${ContentType.TEXT_PLAIN}\n${text}`))
      );
      if (!digest.ok || digest.digest === undefined) {
        return { status: OutboundItemLiveStatus.FAILED, field: digest.field ?? 'contentDigest' };
      }
      const itemId = normalizeUuid(util.generateRandomUUID(false));
      const originDeviceId = await this.identity.getOrCreateDeviceId(nowMs);
      const originSeq = await this.identity.peekNextOriginSeq();
      const contentLength = utf8Encode(text).length;
      const encryptedContent = await this.encryptLocalContent(
        space.encryptedSpaceKeyRef,
        itemId,
        spaceId,
        originDeviceId,
        originSeq,
        contentLength,
        digest.digest,
        text
      );
      if (encryptedContent === null) {
        return { status: OutboundItemLiveStatus.FAILED, field: 'encryptLocalContent' };
      }
      const persisted = await this.persistence.persist({
        spaceId,
        text,
        contentDigest: digest.digest,
        encryptedContent,
        settings,
        nowMs,
        itemId,
        originDeviceId,
        originSeq
      });
      await this.clipboard.applyRetention(spaceId, settings, nowMs);
      const item = persisted.record.item;
      return {
        status: persisted.policy.broadcastAfterCommit ? OutboundItemLiveStatus.READY : OutboundItemLiveStatus.PAUSED,
        payload: toPayload(item.itemId, item.spaceId, item.originDeviceId, item.originSeq, item.hlc,
          item.contentLength, item.contentDigest, item.createdAt, text)
      };
    } catch (_) {
      return { status: OutboundItemLiveStatus.FAILED, field: 'persist' };
    }
  }

  private async encryptLocalContent(ref: string, itemId: string, spaceId: string, originDeviceId: string,
    originSeq: number, contentLength: number, contentDigest: string, text: string): Promise<Uint8Array | null> {
    const nonce = await this.random.randomBytes(NONCE_BYTES);
    if (nonce.length !== NONCE_BYTES) return null;
    const aad = localStorageAad(itemId, spaceId, originDeviceId, originSeq, contentLength, contentDigest);
    const encrypted = await this.huks.encryptBase64Url(ref, encodeBase64Url(nonce),
      encodeBase64Url(utf8Encode(aad)), encodeBase64Url(utf8Encode(text)));
    if (!encrypted.ok || encrypted.body === undefined || encrypted.tag === undefined) return null;
    return utf8Encode(JSON.stringify({ version: 1, nonce: encodeBase64Url(nonce),
      aad: encodeBase64Url(utf8Encode(aad)), body: encrypted.body, tag: encrypted.tag }));
  }
}

function toPayload(itemId: string, spaceId: string, originDeviceId: string, originSeq: number,
  hlc: string, contentLength: number, contentDigest: string, createdAt: number, content: string): JsonObject {
  return JSON.parse(JSON.stringify({ itemId, spaceId, originDeviceId, originSeq, hlc,
    contentType: ContentType.TEXT_PLAIN, contentLength, contentDigest, createdAt, content })) as JsonObject;
}

function localStorageAad(itemId: string, spaceId: string, originDeviceId: string, originSeq: number,
  contentLength: number, contentDigest: string): string {
  return 'EggClip v1 local clipboard storage\n' + `itemId=${itemId}\n` + `spaceId=${spaceId}\n` +
    `originDeviceId=${originDeviceId}\n` + `originSeq=${originSeq}\n` +
    `contentLength=${contentLength}\n` + `contentDigest=${contentDigest}\n`;
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

function normalizeUuid(value: string): string {
  return value.toLowerCase();
}
