import { common } from '@kit.AbilityKit';
import { ContentType } from '../../models/DomainModels';
import {
  ClipboardItem,
  ItemBatchPayload,
  PROTOCOL_MAX_BATCH_ITEMS,
  PROTOCOL_MAX_BATCH_PLAINTEXT_BYTES,
  RequestRangePayload,
  RetentionGap
} from '../../models/ProtocolModels';
import { ClipboardRdbRepository, SpaceRdbRepository } from '../../data/repositories/RdbRepositories';
import { ClipboardItemRecord } from '../../data/repositories/RepositoryCommands';
import { decodeBase64Url, encodeBase64Url } from '../crypto/CryptoVectorService';
import { SpaceKeyHuksService } from '../crypto/SpaceKeyHuksService';

interface StoredContentEnvelope {
  version: number;
  nonce: string;
  aad: string;
  body: string;
  tag: string;
}

export interface OutboundItemBatchResult {
  ok: boolean;
  payload?: ItemBatchPayload;
  field?: string;
}

export class OutboundItemBatchService {
  private readonly clipboard: ClipboardRdbRepository;
  private readonly spaces: SpaceRdbRepository;
  private readonly huks: SpaceKeyHuksService;

  constructor(context: common.Context, huks: SpaceKeyHuksService = new SpaceKeyHuksService()) {
    this.clipboard = new ClipboardRdbRepository(context);
    this.spaces = new SpaceRdbRepository(context);
    this.huks = huks;
  }

  async build(spaceId: string, request: RequestRangePayload, nowMs: number): Promise<OutboundItemBatchResult> {
    const space = await this.spaces.get(spaceId);
    if (space === null || space.encryptedSpaceKeyRef === undefined || space.encryptedSpaceKeyRef.length === 0) {
      return { ok: false, field: 'space' };
    }
    const heads = await this.clipboard.summarizeAvailableSequences(spaceId, nowMs);
    const minimum: Record<string, number> = {};
    const latest: Record<string, number> = {};
    for (let index = 0; index < heads.length; index += 1) {
      minimum[heads[index].originDeviceId] = heads[index].minimumAvailable;
      latest[heads[index].originDeviceId] = heads[index].latestOriginSeq;
    }
    const items: ClipboardItem[] = [];
    const gaps: RetentionGap[] = [];
    let totalBytes = 0;
    for (let rangeIndex = 0; rangeIndex < request.ranges.length; rangeIndex += 1) {
      const range = request.ranges[rangeIndex];
      if (items.length >= PROTOCOL_MAX_BATCH_ITEMS) break;
      const minimumAvailable = minimum[range.originDeviceId];
      const latestAvailable = latest[range.originDeviceId];
      if (minimumAvailable === undefined || latestAvailable === undefined) {
        gaps.push({ originDeviceId: range.originDeviceId, requestedFromSeq: range.fromSeq,
          minimumAvailable: range.toSeq + 1 });
        continue;
      }
      if (range.fromSeq < minimumAvailable) {
        gaps.push({ originDeviceId: range.originDeviceId, requestedFromSeq: range.fromSeq, minimumAvailable });
      }
      const fromSeq = Math.max(range.fromSeq, minimumAvailable);
      const toSeq = Math.min(range.toSeq, latestAvailable);
      if (fromSeq > toSeq) continue;
      const records = await this.clipboard.listByOriginRange(
        spaceId, range.originDeviceId, fromSeq, toSeq, PROTOCOL_MAX_BATCH_ITEMS - items.length
      );
      for (let index = 0; index < records.length; index += 1) {
        const item = await this.restoreRecord(space.encryptedSpaceKeyRef, records[index]);
        if (item === null) {
          gaps.push({ originDeviceId: range.originDeviceId,
            requestedFromSeq: records[index].item.originSeq,
            minimumAvailable: records[index].item.originSeq + 1 });
          continue;
        }
        if (totalBytes + item.contentLength > PROTOCOL_MAX_BATCH_PLAINTEXT_BYTES) break;
        totalBytes += item.contentLength;
        items.push(item);
      }
    }
    if (items.length === 0 && gaps.length === 0) return { ok: false, field: 'empty' };
    return { ok: true, payload: { items, gaps } };
  }

  private async restoreRecord(ref: string, record: ClipboardItemRecord): Promise<ClipboardItem | null> {
    let envelope: StoredContentEnvelope;
    try {
      envelope = JSON.parse(utf8Decode(record.encryptedContent)) as StoredContentEnvelope;
    } catch (_) {
      return null;
    }
    const expectedAad = localStorageAad(record);
    if (envelope.version !== 1 || envelope.aad !== encodeBase64Url(utf8Encode(expectedAad))) return null;
    const decrypted = await this.huks.decryptBase64Url(
      ref, envelope.nonce, envelope.aad, envelope.body, envelope.tag
    );
    if (!decrypted.ok || decrypted.plaintext === undefined) return null;
    const plaintext = decodeBase64Url(decrypted.plaintext);
    if (plaintext === null) return null;
    const content = utf8Decode(plaintext);
    if (content.length === 0 || utf8Encode(content).length !== record.item.contentLength) return null;
    return {
      itemId: record.item.itemId,
      spaceId: record.item.spaceId,
      originDeviceId: record.item.originDeviceId,
      originSeq: record.item.originSeq,
      hlc: record.item.hlc,
      contentType: ContentType.TEXT_PLAIN,
      contentLength: record.item.contentLength,
      contentDigest: record.item.contentDigest,
      createdAt: record.item.createdAt,
      content
    };
  }
}

function localStorageAad(record: ClipboardItemRecord): string {
  return 'EggClip v1 local clipboard storage\n' + `itemId=${record.item.itemId}\n` +
    `spaceId=${record.item.spaceId}\n` + `originDeviceId=${record.item.originDeviceId}\n` +
    `originSeq=${record.item.originSeq}\n` + `contentLength=${record.item.contentLength}\n` +
    `contentDigest=${record.item.contentDigest}\n`;
}

function utf8Encode(value: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) bytes.push(code);
    else if (code <= 0x7ff) bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    else bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
  }
  return new Uint8Array(bytes);
}

function utf8Decode(bytes: Uint8Array): string {
  let value = '';
  for (let index = 0; index < bytes.length;) {
    const first = bytes[index];
    if (first <= 0x7f) { value += String.fromCharCode(first); index += 1; }
    else if ((first & 0xe0) === 0xc0 && index + 1 < bytes.length) {
      value += String.fromCharCode(((first & 0x1f) << 6) | (bytes[index + 1] & 0x3f)); index += 2;
    } else if ((first & 0xf0) === 0xe0 && index + 2 < bytes.length) {
      value += String.fromCharCode(((first & 0x0f) << 12) | ((bytes[index + 1] & 0x3f) << 6) |
        (bytes[index + 2] & 0x3f)); index += 3;
    } else return '';
  }
  return value;
}
