import { estimateUtf8Bytes } from '../utils/TextLimits';

export const DEFAULT_HISTORY_LIMIT: number = 50;
export const DEFAULT_RETENTION_DAYS: number = 7;
export const MAX_HISTORY_LIMIT: number = 100;
export const MAX_CLIPBOARD_TEXT_BYTES: number = 256 * 1024;

export enum DomainValidationError {
  EMPTY_TEXT = 'emptyText',
  TEXT_TOO_LARGE = 'textTooLarge',
  INVALID_HISTORY_LIMIT = 'invalidHistoryLimit',
  INVALID_FIELD = 'invalidField',
  SEQUENCE_OVERFLOW = 'sequenceOverflow'
}

export enum ContentType {
  TEXT_PLAIN = 'text/plain'
}

export enum DeviceTrustState {
  TRUSTED = 'trusted',
  REVOKED = 'revoked'
}

export enum DeviceConnectionState {
  OFFLINE = 'offline',
  CONNECTING = 'connecting',
  ONLINE = 'online',
  AUTH_FAILED = 'authFailed'
}

export enum SpaceState {
  ACTIVE = 'active',
  ROTATING_KEY = 'rotatingKey',
  ARCHIVED = 'archived'
}

export enum ClipboardDedupDecision {
  NEW = 'new',
  DUPLICATE = 'duplicate',
  CONFLICT = 'conflict'
}

export interface ClipboardItem {
  itemId: string;
  spaceId: string;
  originDeviceId: string;
  originSeq: number;
  hlc: string;
  contentType: ContentType;
  contentLength: number;
  contentDigest: string;
  createdAt: number;
  encryptedContentRef?: string;
  plaintext?: string;
}

export interface Device {
  deviceId: string;
  spaceId: string;
  displayName: string;
  identityPublicKeyRef: string;
  trustState: DeviceTrustState;
  connectionState: DeviceConnectionState;
  lastSeenAt?: number;
}

export interface Space {
  spaceId: string;
  displayName: string;
  keyVersion: number;
  state: SpaceState;
  createdAt: number;
}

export interface SyncHead {
  spaceId: string;
  originDeviceId: string;
  latestOriginSeq: number;
  minimumAvailable: number;
  updatedAt: number;
}

export interface AppSettings {
  syncEnabled: boolean;
  autoReceiveEnabled: boolean;
  autoWriteEnabled: boolean;
  historyEnabled: boolean;
  historyLimit: number;
  retentionDays: number;
}

export interface ValidationResult {
  ok: boolean;
  error?: DomainValidationError;
  field?: string;
}

export interface ClipboardItemBuildResult {
  ok: boolean;
  item?: ClipboardItem;
  error?: DomainValidationError;
  field?: string;
}

export interface LocalClipboardItemDraftInput {
  itemId: string;
  spaceId: string;
  originDeviceId: string;
  originSeq: number;
  hlc: HlcTimestamp;
  createdAt: number;
  contentDigest: string;
}

export function defaultAppSettings(): AppSettings {
  return {
    syncEnabled: true,
    autoReceiveEnabled: true,
    autoWriteEnabled: false,
    historyEnabled: true,
    historyLimit: DEFAULT_HISTORY_LIMIT,
    retentionDays: DEFAULT_RETENTION_DAYS
  };
}

export function validateAppSettings(settings: AppSettings): ValidationResult {
  if (settings.historyLimit !== 0 && settings.historyLimit !== 20 &&
    settings.historyLimit !== DEFAULT_HISTORY_LIMIT && settings.historyLimit !== MAX_HISTORY_LIMIT) {
    return { ok: false, error: DomainValidationError.INVALID_HISTORY_LIMIT, field: 'historyLimit' };
  }
  if (!isNonNegativeSafeInteger(settings.retentionDays)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'retentionDays' };
  }
  return { ok: true };
}

export class HlcTimestamp {
  readonly wallTimeMs: number;
  readonly logical: number;

  constructor(wallTimeMs: number, logical: number = 0) {
    this.wallTimeMs = wallTimeMs;
    this.logical = logical;
  }

  tick(nowMs: number): HlcTimestamp {
    if (nowMs > this.wallTimeMs) {
      return new HlcTimestamp(nowMs, 0);
    }
    return new HlcTimestamp(this.wallTimeMs, saturatingAddU16(this.logical));
  }

  observe(remote: HlcTimestamp, nowMs: number): HlcTimestamp {
    const wallTimeMs = Math.max(nowMs, this.wallTimeMs, remote.wallTimeMs);
    if (wallTimeMs === this.wallTimeMs && wallTimeMs === remote.wallTimeMs) {
      return new HlcTimestamp(wallTimeMs, saturatingAddU16(Math.max(this.logical, remote.logical)));
    }
    if (wallTimeMs === this.wallTimeMs) {
      return new HlcTimestamp(wallTimeMs, saturatingAddU16(this.logical));
    }
    if (wallTimeMs === remote.wallTimeMs) {
      return new HlcTimestamp(wallTimeMs, saturatingAddU16(remote.logical));
    }
    return new HlcTimestamp(wallTimeMs, 0);
  }

  compare(other: HlcTimestamp): number {
    if (this.wallTimeMs !== other.wallTimeMs) {
      return this.wallTimeMs < other.wallTimeMs ? -1 : 1;
    }
    if (this.logical !== other.logical) {
      return this.logical < other.logical ? -1 : 1;
    }
    return 0;
  }

  toWire(): string {
    return `${toFixedHex(this.wallTimeMs, 16)}-${toFixedHex(this.logical, 4)}`;
  }
}

export class OriginSeqAllocator {
  private nextValue: number;

  constructor(nextValue: number) {
    this.nextValue = nextValue;
  }

  nextSeq(): number {
    const current = this.nextValue;
    if (!Number.isSafeInteger(current + 1)) {
      return -1;
    }
    this.nextValue = current + 1;
    return current;
  }

  peekNext(): number {
    return this.nextValue;
  }
}

export function buildLocalClipboardItemDraft(
  input: LocalClipboardItemDraftInput,
  text: string
): ClipboardItemBuildResult {
  const actualBytes = estimateUtf8Bytes(text);
  if (actualBytes === 0) {
    return { ok: false, error: DomainValidationError.EMPTY_TEXT, field: 'plaintext' };
  }
  if (actualBytes > MAX_CLIPBOARD_TEXT_BYTES) {
    return { ok: false, error: DomainValidationError.TEXT_TOO_LARGE, field: 'plaintext' };
  }
  const baseValidation = validateClipboardItemFields({
    itemId: input.itemId,
    spaceId: input.spaceId,
    originDeviceId: input.originDeviceId,
    originSeq: input.originSeq,
    hlc: input.hlc.toWire(),
    contentType: ContentType.TEXT_PLAIN,
    contentLength: actualBytes,
    contentDigest: input.contentDigest,
    createdAt: input.createdAt,
    plaintext: text
  });
  if (!baseValidation.ok) {
    return {
      ok: false,
      error: baseValidation.error,
      field: baseValidation.field
    };
  }
  return {
    ok: true,
    item: {
      itemId: input.itemId,
      spaceId: input.spaceId,
      originDeviceId: input.originDeviceId,
      originSeq: input.originSeq,
      hlc: input.hlc.toWire(),
      contentType: ContentType.TEXT_PLAIN,
      contentLength: actualBytes,
      contentDigest: input.contentDigest,
      createdAt: input.createdAt,
      plaintext: text
    }
  };
}

export function deduplicateClipboardItem(existing: ClipboardItem, incoming: ClipboardItem): ClipboardDedupDecision {
  const sameItemId = existing.itemId === incoming.itemId;
  const sameOriginSequence = existing.originDeviceId === incoming.originDeviceId &&
    existing.originSeq === incoming.originSeq;
  const sameDigest = existing.contentDigest === incoming.contentDigest;

  if (sameItemId && sameOriginSequence && sameDigest) {
    return ClipboardDedupDecision.DUPLICATE;
  }
  if (sameItemId || sameOriginSequence) {
    if (sameDigest) {
      return ClipboardDedupDecision.DUPLICATE;
    }
    return ClipboardDedupDecision.CONFLICT;
  }
  return ClipboardDedupDecision.NEW;
}

export function validateClipboardItemFields(item: ClipboardItem): ValidationResult {
  if (!isUuid(item.itemId)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'itemId' };
  }
  if (!isUuid(item.spaceId)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'spaceId' };
  }
  if (!isUuid(item.originDeviceId)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'originDeviceId' };
  }
  if (!isNonNegativeSafeInteger(item.originSeq)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'originSeq' };
  }
  if (!isHlcWireValue(item.hlc)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'hlc' };
  }
  if (item.contentType !== ContentType.TEXT_PLAIN) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'contentType' };
  }
  if (!isNonNegativeSafeInteger(item.contentLength)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'contentLength' };
  }
  if (!isBase64Url(item.contentDigest)) {
    return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'contentDigest' };
  }
  if (item.plaintext !== undefined) {
    const actualBytes = estimateUtf8Bytes(item.plaintext);
    if (actualBytes === 0 || actualBytes !== item.contentLength) {
      return { ok: false, error: DomainValidationError.INVALID_FIELD, field: 'contentLength' };
    }
    if (actualBytes > MAX_CLIPBOARD_TEXT_BYTES) {
      return { ok: false, error: DomainValidationError.TEXT_TOO_LARGE, field: 'plaintext' };
    }
  }
  return { ok: true };
}

function toFixedHex(value: number, width: number): string {
  const hex = Math.trunc(value).toString(16);
  if (hex.length >= width) {
    return hex;
  }
  return '0'.repeat(width - hex.length) + hex;
}

function saturatingAddU16(value: number): number {
  return value >= 0xffff ? 0xffff : value + 1;
}

function isNonNegativeSafeInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);
}

function isBase64Url(value: string): boolean {
  return /^[A-Za-z0-9_-]+$/.test(value);
}

function isHlcWireValue(value: string): boolean {
  return /^[0-9a-f]{16}-[0-9a-f]{4}$/.test(value);
}
