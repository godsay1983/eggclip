import { decodeBase64Url } from '../crypto/CryptoVectorService';
import { JsonObject } from '../../models/ProtocolModels';

const INVITATION_PREFIX: string = 'eggclip://pair?p=';
const PAIRING_SECRET_BYTES: number = 32;
const IDENTITY_PUBLIC_KEY_BYTES: number = 32;
const MAX_INVITATION_URI_LENGTH: number = 4096;
const MAX_INVITATION_PAYLOAD_BYTES: number = 3072;
const MAX_ISSUER_DEVICE_NAME_CHARS: number = 32;

export enum PairingInvitationError {
  EMPTY = 'empty',
  TOO_LARGE = 'tooLarge',
  INVALID_SCHEME = 'invalidScheme',
  INVALID_PAYLOAD = 'invalidPayload',
  INVALID_FIELD = 'invalidField',
  EXPIRED = 'expired'
}

export interface PairingInvitationPayload {
  app: string;
  version: number;
  kind: string;
  invitationId?: string;
  spaceId: string;
  spaceKeyVersion: number;
  issuerDeviceName?: string;
  issuerDeviceId: string;
  issuerIdentityPublicKey: string;
  pairingSecret: string;
  expiresAtMs: number;
}

export interface PairingInvitationSummary {
  invitationId?: string;
  spaceId: string;
  spaceShortId: string;
  spaceKeyVersion: number;
  issuerDeviceName: string;
  issuerDeviceId: string;
  issuerShortFingerprint: string;
  expiresAtMs: number;
  expiresInSeconds: number;
  confirmationCode: string;
}

export interface PairingInvitationParseResult {
  ok: boolean;
  payload?: PairingInvitationPayload;
  summary?: PairingInvitationSummary;
  error?: PairingInvitationError;
  field?: string;
}

export class PairingInvitationService {
  parse(invitation: string, nowMs: number): PairingInvitationParseResult {
    const normalized = invitation.trim();
    if (normalized.length === 0) {
      return { ok: false, error: PairingInvitationError.EMPTY };
    }
    if (normalized.length > MAX_INVITATION_URI_LENGTH) {
      return { ok: false, error: PairingInvitationError.TOO_LARGE };
    }
    if (!normalized.startsWith(INVITATION_PREFIX)) {
      return { ok: false, error: PairingInvitationError.INVALID_SCHEME };
    }
    const encodedPayload = normalized.substring(INVITATION_PREFIX.length);
    const payloadBytes = decodeBase64Url(encodedPayload);
    if (payloadBytes === null) {
      return { ok: false, error: PairingInvitationError.INVALID_PAYLOAD };
    }
    if (payloadBytes.length > MAX_INVITATION_PAYLOAD_BYTES) {
      return { ok: false, error: PairingInvitationError.TOO_LARGE };
    }
    const payloadText = decodeUtf8(payloadBytes);
    if (payloadText === null) {
      return { ok: false, error: PairingInvitationError.INVALID_PAYLOAD };
    }
    const payload = parsePayloadJson(payloadText);
    if (payload === null) {
      return { ok: false, error: PairingInvitationError.INVALID_PAYLOAD };
    }
    const validation = validatePayload(payload, nowMs);
    if (!validation.ok) {
      return validation;
    }
    return {
      ok: true,
      payload,
      summary: buildSummary(payload, nowMs, payloadBytes)
    };
  }

  describeError(result: PairingInvitationParseResult): string {
    switch (result.error) {
      case PairingInvitationError.EMPTY:
        return '请输入或粘贴桌面端生成的配对邀请';
      case PairingInvitationError.TOO_LARGE:
        return '配对邀请过长，已拒绝处理';
      case PairingInvitationError.INVALID_SCHEME:
        return '不是 EggClip 配对邀请，请使用 eggclip://pair 开头的字符串';
      case PairingInvitationError.INVALID_PAYLOAD:
        return '配对邀请内容无法解析';
      case PairingInvitationError.INVALID_FIELD:
        return `配对邀请字段无效：${result.field ?? '未知字段'}`;
      case PairingInvitationError.EXPIRED:
        return '配对邀请已过期，请在桌面端重新生成';
      default:
        return '配对邀请无效';
    }
  }
}

function parsePayloadJson(payloadText: string): PairingInvitationPayload | null {
  try {
    const value = JSON.parse(payloadText) as JsonObject;
    return {
      app: readString(value, 'app'),
      version: readNumber(value, 'version'),
      kind: readString(value, 'kind'),
      invitationId: readOptionalString(value, 'invitationId'),
      spaceId: readString(value, 'spaceId'),
      spaceKeyVersion: readNumber(value, 'spaceKeyVersion'),
      issuerDeviceName: readOptionalString(value, 'issuerDeviceName'),
      issuerDeviceId: readString(value, 'issuerDeviceId'),
      issuerIdentityPublicKey: readString(value, 'issuerIdentityPublicKey'),
      pairingSecret: readString(value, 'pairingSecret'),
      expiresAtMs: readNumber(value, 'expiresAtMs')
    };
  } catch (_) {
    return null;
  }
}

function validatePayload(payload: PairingInvitationPayload, nowMs: number): PairingInvitationParseResult {
  if (payload.app !== 'eggclip') {
    return invalidField('app');
  }
  if (payload.version !== 1) {
    return invalidField('version');
  }
  if (payload.kind !== 'pairingInvitation') {
    return invalidField('kind');
  }
  if (payload.invitationId !== undefined && !isUuid(payload.invitationId)) {
    return invalidField('invitationId');
  }
  if (!isUuid(payload.spaceId)) {
    return invalidField('spaceId');
  }
  if (!Number.isSafeInteger(payload.spaceKeyVersion) || payload.spaceKeyVersion <= 0) {
    return invalidField('spaceKeyVersion');
  }
  if (payload.issuerDeviceName !== undefined && normalizeIssuerDeviceName(payload.issuerDeviceName) === null) {
    return invalidField('issuerDeviceName');
  }
  if (!isUuid(payload.issuerDeviceId)) {
    return invalidField('issuerDeviceId');
  }
  if (!hasBase64UrlLength(payload.issuerIdentityPublicKey, IDENTITY_PUBLIC_KEY_BYTES)) {
    return invalidField('issuerIdentityPublicKey');
  }
  if (!hasBase64UrlLength(payload.pairingSecret, PAIRING_SECRET_BYTES)) {
    return invalidField('pairingSecret');
  }
  if (!Number.isSafeInteger(payload.expiresAtMs) || payload.expiresAtMs <= 0) {
    return invalidField('expiresAtMs');
  }
  if (payload.expiresAtMs <= nowMs) {
    return { ok: false, error: PairingInvitationError.EXPIRED };
  }
  return { ok: true };
}

function buildSummary(payload: PairingInvitationPayload, nowMs: number, payloadBytes: Uint8Array): PairingInvitationSummary {
  return {
    invitationId: payload.invitationId,
    spaceId: payload.spaceId,
    spaceShortId: payload.spaceId.substring(payload.spaceId.length - 8),
    spaceKeyVersion: payload.spaceKeyVersion,
    issuerDeviceName: normalizeIssuerDeviceName(payload.issuerDeviceName) ?? `桌面端 #${payload.issuerIdentityPublicKey.substring(0, 8)}`,
    issuerDeviceId: payload.issuerDeviceId,
    issuerShortFingerprint: payload.issuerIdentityPublicKey.substring(0, 8),
    expiresAtMs: payload.expiresAtMs,
    expiresInSeconds: Math.max(0, Math.floor((payload.expiresAtMs - nowMs) / 1000)),
    confirmationCode: confirmationCode(payloadBytes)
  };
}

function confirmationCode(payloadBytes: Uint8Array): string {
  const digest = sha256(payloadBytes);
  const value = (((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) >>> 0) % 1000000;
  return value.toString().padStart(6, '0');
}

function readString(value: JsonObject, key: string): string {
  const field = value[key];
  if (typeof field !== 'string') {
    throw new Error(`invalid ${key}`);
  }
  return field;
}

function readOptionalString(value: JsonObject, key: string): string | undefined {
  const field = value[key];
  if (field === undefined) {
    return undefined;
  }
  if (typeof field !== 'string') {
    throw new Error(`invalid ${key}`);
  }
  return field;
}

function readNumber(value: JsonObject, key: string): number {
  const field = value[key];
  if (typeof field !== 'number') {
    throw new Error(`invalid ${key}`);
  }
  return field;
}

function invalidField(field: string): PairingInvitationParseResult {
  return { ok: false, error: PairingInvitationError.INVALID_FIELD, field };
}

function hasBase64UrlLength(value: string, expectedBytes: number): boolean {
  const decoded = decodeBase64Url(value);
  return decoded !== null && decoded.length === expectedBytes;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);
}

function normalizeIssuerDeviceName(value: string | undefined): string | null {
  if (value === undefined) {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }
  let normalized = '';
  for (let index = 0; index < trimmed.length && normalized.length < MAX_ISSUER_DEVICE_NAME_CHARS; index += 1) {
    const code = trimmed.charCodeAt(index);
    if (code >= 0x20 && code !== 0x7f) {
      normalized += trimmed.charAt(index);
    }
  }
  if (normalized.length === 0 || normalized.length !== trimmed.length) {
    return null;
  }
  return normalized;
}

function sha256(input: Uint8Array): Uint8Array {
  const k: number[] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];
  const bitLengthHigh = Math.floor(input.length / 0x20000000);
  const bitLengthLow = (input.length << 3) >>> 0;
  const paddedLength = Math.ceil((input.length + 9) / 64) * 64;
  const data = new Uint8Array(paddedLength);
  data.set(input);
  data[input.length] = 0x80;
  writeU32(data, paddedLength - 8, bitLengthHigh);
  writeU32(data, paddedLength - 4, bitLengthLow);

  let h0 = 0x6a09e667;
  let h1 = 0xbb67ae85;
  let h2 = 0x3c6ef372;
  let h3 = 0xa54ff53a;
  let h4 = 0x510e527f;
  let h5 = 0x9b05688c;
  let h6 = 0x1f83d9ab;
  let h7 = 0x5be0cd19;
  const w: number[] = new Array<number>(64);

  for (let offset = 0; offset < data.length; offset += 64) {
    for (let index = 0; index < 16; index += 1) {
      w[index] = readU32(data, offset + index * 4);
    }
    for (let index = 16; index < 64; index += 1) {
      const s0 = rotateRight(w[index - 15], 7) ^ rotateRight(w[index - 15], 18) ^ (w[index - 15] >>> 3);
      const s1 = rotateRight(w[index - 2], 17) ^ rotateRight(w[index - 2], 19) ^ (w[index - 2] >>> 10);
      w[index] = add32(add32(add32(w[index - 16], s0), w[index - 7]), s1);
    }

    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;
    let f = h5;
    let g = h6;
    let h = h7;

    for (let index = 0; index < 64; index += 1) {
      const s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      const ch = (e & f) ^ ((~e) & g);
      const temp1 = add32(add32(add32(add32(h, s1), ch), k[index]), w[index]);
      const s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = add32(s0, maj);
      h = g;
      g = f;
      f = e;
      e = add32(d, temp1);
      d = c;
      c = b;
      b = a;
      a = add32(temp1, temp2);
    }

    h0 = add32(h0, a);
    h1 = add32(h1, b);
    h2 = add32(h2, c);
    h3 = add32(h3, d);
    h4 = add32(h4, e);
    h5 = add32(h5, f);
    h6 = add32(h6, g);
    h7 = add32(h7, h);
  }

  const digest = new Uint8Array(32);
  writeU32(digest, 0, h0);
  writeU32(digest, 4, h1);
  writeU32(digest, 8, h2);
  writeU32(digest, 12, h3);
  writeU32(digest, 16, h4);
  writeU32(digest, 20, h5);
  writeU32(digest, 24, h6);
  writeU32(digest, 28, h7);
  return digest;
}

function add32(left: number, right: number): number {
  return (left + right) >>> 0;
}

function rotateRight(value: number, bits: number): number {
  return (value >>> bits) | (value << (32 - bits));
}

function readU32(data: Uint8Array, offset: number): number {
  return ((data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]) >>> 0;
}

function writeU32(data: Uint8Array, offset: number, value: number): void {
  data[offset] = (value >>> 24) & 0xff;
  data[offset + 1] = (value >>> 16) & 0xff;
  data[offset + 2] = (value >>> 8) & 0xff;
  data[offset + 3] = value & 0xff;
}

function decodeUtf8(bytes: Uint8Array): string | null {
  let output = '';
  for (let index = 0; index < bytes.length; index += 1) {
    const first = bytes[index];
    if (first <= 0x7f) {
      output += String.fromCharCode(first);
    } else if (first >= 0xc2 && first <= 0xdf) {
      if (index + 1 >= bytes.length) {
        return null;
      }
      const second = bytes[index + 1];
      if ((second & 0xc0) !== 0x80) {
        return null;
      }
      output += String.fromCharCode(((first & 0x1f) << 6) | (second & 0x3f));
      index += 1;
    } else if (first >= 0xe0 && first <= 0xef) {
      if (index + 2 >= bytes.length) {
        return null;
      }
      const second = bytes[index + 1];
      const third = bytes[index + 2];
      if ((second & 0xc0) !== 0x80 || (third & 0xc0) !== 0x80) {
        return null;
      }
      output += String.fromCharCode(((first & 0x0f) << 12) | ((second & 0x3f) << 6) | (third & 0x3f));
      index += 2;
    } else if (first >= 0xf0 && first <= 0xf4) {
      if (index + 3 >= bytes.length) {
        return null;
      }
      const second = bytes[index + 1];
      const third = bytes[index + 2];
      const fourth = bytes[index + 3];
      if ((second & 0xc0) !== 0x80 || (third & 0xc0) !== 0x80 || (fourth & 0xc0) !== 0x80) {
        return null;
      }
      const codePoint = ((first & 0x07) << 18) | ((second & 0x3f) << 12) |
        ((third & 0x3f) << 6) | (fourth & 0x3f);
      if (codePoint > 0x10ffff) {
        return null;
      }
      const offset = codePoint - 0x10000;
      output += String.fromCharCode(0xd800 + (offset >> 10), 0xdc00 + (offset & 0x3ff));
      index += 3;
    } else {
      return null;
    }
  }
  return output;
}
