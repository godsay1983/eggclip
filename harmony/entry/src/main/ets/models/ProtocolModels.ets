import { estimateUtf8Bytes } from '../utils/TextLimits';

export const PROTOCOL_VERSION: number = 1;
export const PROTOCOL_MAX_FRAME_BYTES: number = 1024 * 1024;
export const PROTOCOL_MAX_TEXT_BYTES: number = 256 * 1024;
export const PROTOCOL_MAX_BATCH_ITEMS: number = 100;
export const PROTOCOL_MAX_BATCH_PLAINTEXT_BYTES: number = 512 * 1024;
export const PROTOCOL_HANDSHAKE_TIMEOUT_SECONDS: number = 8;
export const PROTOCOL_HEARTBEAT_INTERVAL_SECONDS: number = 20;
export const PROTOCOL_IDLE_DISCONNECT_SECONDS: number = 60;

export enum MessageType {
  CLIENT_HELLO = 'CLIENT_HELLO',
  SERVER_HELLO = 'SERVER_HELLO',
  AUTH_PROOF = 'AUTH_PROOF',
  AUTH_OK = 'AUTH_OK',
  AUTH_ERROR = 'AUTH_ERROR',
  SYNC_HEADS = 'SYNC_HEADS',
  REQUEST_RANGE = 'REQUEST_RANGE',
  ITEM_BATCH = 'ITEM_BATCH',
  ITEM_LIVE = 'ITEM_LIVE',
  ITEM_ACK = 'ITEM_ACK',
  DEVICE_REVOKED = 'DEVICE_REVOKED',
  SPACE_KEY_ROTATED = 'SPACE_KEY_ROTATED',
  PING = 'PING',
  PONG = 'PONG',
  ERROR = 'ERROR'
}

export enum ProtocolEnvelopeKind {
  PRE_AUTH = 'preAuth',
  ENCRYPTED = 'encrypted'
}

export enum ProtocolErrorCode {
  INVALID_JSON = 'invalidJson',
  UNSUPPORTED_VERSION = 'unsupportedVersion',
  UNKNOWN_MESSAGE_TYPE = 'unknownMessageType',
  MISSING_PAYLOAD = 'missingPayload',
  MISSING_CIPHERTEXT = 'missingCiphertext',
  PLAINTEXT_AFTER_AUTH = 'plaintextAfterAuth',
  CIPHERTEXT_BEFORE_AUTH = 'ciphertextBeforeAuth',
  INVALID_FIELD = 'invalidField',
  TEXT_TOO_LARGE = 'textTooLarge'
}

export enum AeadAlgorithm {
  AES_256_GCM = 'AES-256-GCM'
}

export enum Capability {
  TEXT_PLAIN = 'textPlain',
  SYNC_HEADS = 'syncHeads',
  ITEM_BATCH = 'itemBatch',
  ITEM_LIVE = 'itemLive'
}

export enum ContentType {
  TEXT_PLAIN = 'text/plain'
}

export interface CiphertextFrame {
  algorithm: AeadAlgorithm;
  keyId: string;
  nonce: string;
  aad: string;
  body: string;
  tag: string;
}

export interface ParsedEnvelope {
  kind: ProtocolEnvelopeKind;
  messageType: MessageType;
  messageId: string;
  sessionCounter: number;
  payload?: JsonObject;
  ciphertext?: CiphertextFrame;
}

export interface ProtocolParseResult {
  ok: boolean;
  envelope?: ParsedEnvelope;
  error?: ProtocolErrorCode;
  field?: string;
}

export interface HelloPayload {
  spaceId: string;
  deviceId: string;
  identityPublicKey: string;
  ephemeralPublicKey: string;
  capabilities: Capability[];
}

export interface HelloPayloadResult {
  ok: boolean;
  payload?: HelloPayload;
  error?: ProtocolErrorCode;
  field?: string;
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
  content: string;
}

export interface ClipboardItemResult {
  ok: boolean;
  item?: ClipboardItem;
  error?: ProtocolErrorCode;
  field?: string;
}

export interface SyncHeadsPayload {
  heads: Record<string, number>;
  minimumAvailable: Record<string, number>;
}

export type JsonValue = Object | string | number | boolean | null;
export type JsonObject = Record<string, JsonValue>;

interface RawEnvelope {
  version?: JsonValue;
  type?: JsonValue;
  messageId?: JsonValue;
  sessionCounter?: JsonValue;
  payload?: JsonValue;
  ciphertext?: JsonValue;
}

export class ProtocolParser {
  parseEnvelope(input: string): ProtocolParseResult {
    if (estimateUtf8Bytes(input) > PROTOCOL_MAX_FRAME_BYTES) {
      return { ok: false, error: ProtocolErrorCode.TEXT_TOO_LARGE, field: 'frame' };
    }

    let raw: RawEnvelope;
    try {
      raw = JSON.parse(input) as RawEnvelope;
    } catch (_) {
      return { ok: false, error: ProtocolErrorCode.INVALID_JSON };
    }

    if (!isJsonObject(raw as Object)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'envelope' };
    }
    if (raw.version !== PROTOCOL_VERSION) {
      return { ok: false, error: ProtocolErrorCode.UNSUPPORTED_VERSION, field: 'version' };
    }
    if (typeof raw.messageId !== 'string' || !isUuid(raw.messageId)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'messageId' };
    }
    if (typeof raw.sessionCounter !== 'number' || !isNonNegativeSafeInteger(raw.sessionCounter)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'sessionCounter' };
    }
    if (typeof raw.type !== 'string') {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'type' };
    }

    const messageType = parseMessageType(raw.type);
    if (messageType === null) {
      return { ok: false, error: ProtocolErrorCode.UNKNOWN_MESSAGE_TYPE, field: 'type' };
    }

    const hasPayload = raw.payload !== undefined;
    const hasCiphertext = raw.ciphertext !== undefined;
    if (hasPayload && hasCiphertext) {
      return this.rejectMixedAuth(messageType);
    }
    if (hasPayload) {
      if (!isPreAuthAllowed(messageType)) {
        return { ok: false, error: ProtocolErrorCode.PLAINTEXT_AFTER_AUTH, field: 'payload' };
      }
      if (!isJsonObject(raw.payload)) {
        return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'payload' };
      }
      const payload = raw.payload as JsonObject;
      return {
        ok: true,
        envelope: {
          kind: ProtocolEnvelopeKind.PRE_AUTH,
          messageType,
          messageId: raw.messageId,
          sessionCounter: raw.sessionCounter,
          payload
        }
      };
    }
    if (hasCiphertext) {
      if (!isEncryptedAllowed(messageType)) {
        return { ok: false, error: ProtocolErrorCode.CIPHERTEXT_BEFORE_AUTH, field: 'ciphertext' };
      }
      const ciphertextResult = parseCiphertext(raw.ciphertext);
      if (ciphertextResult === null) {
        return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'ciphertext' };
      }
      return {
        ok: true,
        envelope: {
          kind: ProtocolEnvelopeKind.ENCRYPTED,
          messageType,
          messageId: raw.messageId,
          sessionCounter: raw.sessionCounter,
          ciphertext: ciphertextResult
        }
      };
    }

    return {
      ok: false,
      error: isPreAuthAllowed(messageType) ? ProtocolErrorCode.MISSING_PAYLOAD : ProtocolErrorCode.MISSING_CIPHERTEXT
    };
  }

  parseHelloPayload(value: JsonValue | undefined): HelloPayloadResult {
    if (value === undefined || !isJsonObject(value)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'payload' };
    }
    const payloadObject = value as JsonObject;
    const capabilitiesValue = payloadObject.capabilities;
    if (!Array.isArray(capabilitiesValue)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'capabilities' };
    }

    const capabilities: Capability[] = [];
    const capabilityValues = capabilitiesValue as string[];
    for (const capabilityValue of capabilityValues) {
      if (typeof capabilityValue !== 'string') {
        return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'capabilities' };
      }
      const capability = parseCapability(capabilityValue);
      if (capability === null) {
        return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'capabilities' };
      }
      capabilities.push(capability);
    }
    if (capabilities.length === 0) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'capabilities' };
    }

    const payload: HelloPayload = {
      spaceId: getString(payloadObject, 'spaceId'),
      deviceId: getString(payloadObject, 'deviceId'),
      identityPublicKey: getString(payloadObject, 'identityPublicKey'),
      ephemeralPublicKey: getString(payloadObject, 'ephemeralPublicKey'),
      capabilities
    };
    if (!isUuid(payload.spaceId)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'spaceId' };
    }
    if (!isUuid(payload.deviceId)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'deviceId' };
    }
    if (!isBase64Url(payload.identityPublicKey)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'identityPublicKey' };
    }
    if (!isBase64Url(payload.ephemeralPublicKey)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'ephemeralPublicKey' };
    }
    return { ok: true, payload };
  }

  parseClipboardItem(input: string): ClipboardItemResult {
    let value: JsonObject;
    try {
      value = JSON.parse(input) as JsonObject;
    } catch (_) {
      return { ok: false, error: ProtocolErrorCode.INVALID_JSON };
    }
    if (!isJsonObject(value)) {
      return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'item' };
    }
    const itemObject = value as JsonObject;

    const item: ClipboardItem = {
      itemId: getString(itemObject, 'itemId'),
      spaceId: getString(itemObject, 'spaceId'),
      originDeviceId: getString(itemObject, 'originDeviceId'),
      originSeq: getNumber(itemObject, 'originSeq'),
      hlc: getString(itemObject, 'hlc'),
      contentType: getString(itemObject, 'contentType') as ContentType,
      contentLength: getNumber(itemObject, 'contentLength'),
      contentDigest: getString(itemObject, 'contentDigest'),
      createdAt: getNumber(itemObject, 'createdAt'),
      content: getString(itemObject, 'content')
    };

    return validateClipboardItem(item);
  }

  private rejectMixedAuth(messageType: MessageType): ProtocolParseResult {
    if (isPreAuthAllowed(messageType)) {
      return { ok: false, error: ProtocolErrorCode.CIPHERTEXT_BEFORE_AUTH, field: 'ciphertext' };
    }
    return { ok: false, error: ProtocolErrorCode.PLAINTEXT_AFTER_AUTH, field: 'payload' };
  }
}

function parseCiphertext(value: JsonValue | undefined): CiphertextFrame | null {
  if (value === undefined || !isJsonObject(value)) {
    return null;
  }
  const ciphertextObject = value as JsonObject;
  if (ciphertextObject.algorithm !== AeadAlgorithm.AES_256_GCM) {
    return null;
  }
  const ciphertext: CiphertextFrame = {
    algorithm: AeadAlgorithm.AES_256_GCM,
    keyId: getString(ciphertextObject, 'keyId'),
    nonce: getString(ciphertextObject, 'nonce'),
    aad: getString(ciphertextObject, 'aad'),
    body: getString(ciphertextObject, 'body'),
    tag: getString(ciphertextObject, 'tag')
  };
  if (ciphertext.keyId.length === 0 || ciphertext.keyId.length > 128) {
    return null;
  }
  if (!isBase64Url(ciphertext.nonce) || !isBase64Url(ciphertext.aad) ||
    !isBase64Url(ciphertext.body) || !isBase64Url(ciphertext.tag)) {
    return null;
  }
  return ciphertext;
}

function validateClipboardItem(item: ClipboardItem): ClipboardItemResult {
  if (!isUuid(item.itemId)) {
    return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'itemId' };
  }
  if (!isUuid(item.spaceId)) {
    return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'spaceId' };
  }
  if (!isUuid(item.originDeviceId)) {
    return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'originDeviceId' };
  }
  if (!isNonNegativeSafeInteger(item.originSeq)) {
    return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'originSeq' };
  }
  if (item.hlc.length === 0 || item.contentType !== ContentType.TEXT_PLAIN) {
    return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'contentType' };
  }
  if (!isBase64Url(item.contentDigest)) {
    return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'contentDigest' };
  }
  const actualBytes = estimateUtf8Bytes(item.content);
  if (actualBytes === 0 || actualBytes !== item.contentLength) {
    return { ok: false, error: ProtocolErrorCode.INVALID_FIELD, field: 'contentLength' };
  }
  if (actualBytes > PROTOCOL_MAX_TEXT_BYTES) {
    return { ok: false, error: ProtocolErrorCode.TEXT_TOO_LARGE, field: 'content' };
  }
  return { ok: true, item };
}

function parseMessageType(value: string): MessageType | null {
  switch (value) {
    case MessageType.CLIENT_HELLO:
      return MessageType.CLIENT_HELLO;
    case MessageType.SERVER_HELLO:
      return MessageType.SERVER_HELLO;
    case MessageType.AUTH_PROOF:
      return MessageType.AUTH_PROOF;
    case MessageType.AUTH_OK:
      return MessageType.AUTH_OK;
    case MessageType.AUTH_ERROR:
      return MessageType.AUTH_ERROR;
    case MessageType.SYNC_HEADS:
      return MessageType.SYNC_HEADS;
    case MessageType.REQUEST_RANGE:
      return MessageType.REQUEST_RANGE;
    case MessageType.ITEM_BATCH:
      return MessageType.ITEM_BATCH;
    case MessageType.ITEM_LIVE:
      return MessageType.ITEM_LIVE;
    case MessageType.ITEM_ACK:
      return MessageType.ITEM_ACK;
    case MessageType.DEVICE_REVOKED:
      return MessageType.DEVICE_REVOKED;
    case MessageType.SPACE_KEY_ROTATED:
      return MessageType.SPACE_KEY_ROTATED;
    case MessageType.PING:
      return MessageType.PING;
    case MessageType.PONG:
      return MessageType.PONG;
    case MessageType.ERROR:
      return MessageType.ERROR;
    default:
      return null;
  }
}

function parseCapability(value: string): Capability | null {
  switch (value) {
    case Capability.TEXT_PLAIN:
      return Capability.TEXT_PLAIN;
    case Capability.SYNC_HEADS:
      return Capability.SYNC_HEADS;
    case Capability.ITEM_BATCH:
      return Capability.ITEM_BATCH;
    case Capability.ITEM_LIVE:
      return Capability.ITEM_LIVE;
    default:
      return null;
  }
}

function isPreAuthAllowed(messageType: MessageType): boolean {
  return messageType === MessageType.CLIENT_HELLO ||
    messageType === MessageType.SERVER_HELLO ||
    messageType === MessageType.AUTH_PROOF ||
    messageType === MessageType.AUTH_OK ||
    messageType === MessageType.AUTH_ERROR ||
    messageType === MessageType.ERROR;
}

function isEncryptedAllowed(messageType: MessageType): boolean {
  return messageType === MessageType.SYNC_HEADS ||
    messageType === MessageType.REQUEST_RANGE ||
    messageType === MessageType.ITEM_BATCH ||
    messageType === MessageType.ITEM_LIVE ||
    messageType === MessageType.ITEM_ACK ||
    messageType === MessageType.DEVICE_REVOKED ||
    messageType === MessageType.SPACE_KEY_ROTATED ||
    messageType === MessageType.PING ||
    messageType === MessageType.PONG ||
    messageType === MessageType.ERROR;
}

function isJsonObject(value: Object | JsonValue | undefined): boolean {
  return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value);
}

function getString(value: JsonObject, field: string): string {
  const fieldValue = value[field];
  return typeof fieldValue === 'string' ? fieldValue : '';
}

function getNumber(value: JsonObject, field: string): number {
  const fieldValue = value[field];
  return typeof fieldValue === 'number' ? fieldValue : -1;
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
