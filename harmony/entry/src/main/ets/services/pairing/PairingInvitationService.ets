import { decodeBase64Url } from '../crypto/CryptoVectorService';
import { sha256 } from '../crypto/Sha256Service';
import { JsonObject, JsonValue } from '../../models/ProtocolModels';

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
  connectionHints?: PairingConnectionHints;
}

export interface PairingConnectionEndpoint {
  host: string;
  port: number;
}

export interface PairingConnectionHints {
  transport: string;
  endpoints: PairingConnectionEndpoint[];
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
  endpoints: PairingConnectionEndpoint[];
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

}

function parsePayloadJson(payloadText: string): PairingInvitationPayload | null {
  try {
    const value = JSON.parse(payloadText) as JsonObject;
    const payload: PairingInvitationPayload = {
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
    const connectionHints = parseConnectionHints(value.connectionHints);
    if (connectionHints !== null) payload.connectionHints = connectionHints;
    return payload;
  } catch (_) {
    return null;
  }
}

function validatePayload(payload: PairingInvitationPayload, nowMs: number): PairingInvitationParseResult {
  if (payload.app !== 'eggclip') {
    return invalidField('app');
  }
  if (payload.version !== 2) {
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
  if (payload.connectionHints !== undefined &&
    (payload.connectionHints.transport !== 'ws' || payload.connectionHints.endpoints.length === 0 ||
      payload.connectionHints.endpoints.length > 5)) {
    return invalidField('connectionHints');
  }
  return { ok: true };
}

function buildSummary(payload: PairingInvitationPayload, nowMs: number, payloadBytes: Uint8Array): PairingInvitationSummary {
  return {
    invitationId: payload.invitationId,
    spaceId: payload.spaceId,
    spaceShortId: payload.spaceId.substring(payload.spaceId.length - 8),
    spaceKeyVersion: payload.spaceKeyVersion,
    issuerDeviceName: normalizeIssuerDeviceName(payload.issuerDeviceName) ?? `EggClip Desktop #${payload.issuerIdentityPublicKey.substring(0, 8)}`,
    issuerDeviceId: payload.issuerDeviceId,
    issuerShortFingerprint: payload.issuerIdentityPublicKey.substring(0, 8),
    expiresAtMs: payload.expiresAtMs,
    expiresInSeconds: Math.max(0, Math.floor((payload.expiresAtMs - nowMs) / 1000)),
    confirmationCode: confirmationCode(payloadBytes),
    endpoints: payload.connectionHints?.endpoints ?? []
  };
}

function parseConnectionHints(value: JsonValue | undefined): PairingConnectionHints | null {
  if (value === undefined) return null;
  if (typeof value !== 'object' || value === null) throw new Error('invalid connectionHints');
  const object = value as JsonObject;
  if (object.transport !== 'ws' || !Array.isArray(object.endpoints)) throw new Error('invalid connectionHints');
  const values = object.endpoints as JsonValue[];
  if (values.length === 0 || values.length > 5) throw new Error('invalid endpoints');
  const endpoints: PairingConnectionEndpoint[] = [];
  for (let index = 0; index < values.length; index += 1) {
    const endpoint = values[index];
    if (typeof endpoint !== 'object' || endpoint === null) throw new Error('invalid endpoint');
    const candidate = endpoint as JsonObject;
    if (typeof candidate.host !== 'string' || typeof candidate.port !== 'number' ||
      !isIpv4(candidate.host) || !Number.isInteger(candidate.port) || candidate.port < 1 || candidate.port > 65535) {
      throw new Error('invalid endpoint');
    }
    endpoints.push({ host: candidate.host, port: candidate.port });
  }
  return { transport: 'ws', endpoints };
}

function isIpv4(value: string): boolean {
  const parts = value.split('.');
  if (parts.length !== 4) return false;
  for (let index = 0; index < parts.length; index += 1) {
    if (!/^\d{1,3}$/.test(parts[index])) return false;
    const octet = Number(parts[index]);
    if (octet < 0 || octet > 255) return false;
  }
  return value !== '0.0.0.0' && !value.startsWith('127.');
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
