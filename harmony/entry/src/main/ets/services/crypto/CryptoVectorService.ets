export enum CryptoVectorErrorCode {
  INVALID_JSON = 'invalidJson',
  INVALID_FIELD = 'invalidField',
  INVALID_BASE64URL = 'invalidBase64url',
  INVALID_LENGTH = 'invalidLength',
  REPLAY = 'replay'
}

export interface CryptoVectorValidationResult {
  ok: boolean;
  error?: CryptoVectorErrorCode;
  field?: string;
}

export enum SessionDirection {
  CLIENT_TO_SERVER = 'clientToServer',
  SERVER_TO_CLIENT = 'serverToClient'
}

interface Ed25519SignatureVector {
  algorithm?: Object | string | number | boolean | null;
  privateSeed?: Object | string | number | boolean | null;
  publicKey?: Object | string | number | boolean | null;
  message?: Object | string | number | boolean | null;
  signature?: Object | string | number | boolean | null;
}

interface X25519SharedSecretVector {
  algorithm?: Object | string | number | boolean | null;
  alicePrivateKey?: Object | string | number | boolean | null;
  alicePublicKey?: Object | string | number | boolean | null;
  bobPrivateKey?: Object | string | number | boolean | null;
  bobPublicKey?: Object | string | number | boolean | null;
  sharedSecret?: Object | string | number | boolean | null;
}

interface HkdfSha256Vector {
  algorithm?: Object | string | number | boolean | null;
  ikm?: Object | string | number | boolean | null;
  salt?: Object | string | number | boolean | null;
  info?: Object | string | number | boolean | null;
  length?: Object | string | number | boolean | null;
  prk?: Object | string | number | boolean | null;
  okm?: Object | string | number | boolean | null;
}

interface AesGcmVector {
  algorithm?: Object | string | number | boolean | null;
  key?: Object | string | number | boolean | null;
  nonce?: Object | string | number | boolean | null;
  aad?: Object | string | number | boolean | null;
  plaintext?: Object | string | number | boolean | null;
  ciphertext?: Object | string | number | boolean | null;
  tag?: Object | string | number | boolean | null;
  tamperedTag?: Object | string | number | boolean | null;
}

interface ReplayCounterVector {
  algorithm?: Object | string | number | boolean | null;
  accepted?: number[];
  rejected?: RejectedCounter[];
}

interface SessionKeysVector {
  algorithm?: Object | string | number | boolean | null;
  sharedSecret?: Object | string | number | boolean | null;
  transcriptSalt?: Object | string | number | boolean | null;
  clientToServerInfo?: Object | string | number | boolean | null;
  serverToClientInfo?: Object | string | number | boolean | null;
  clientToServerKey?: Object | string | number | boolean | null;
  serverToClientKey?: Object | string | number | boolean | null;
  counter?: Object | string | number | boolean | null;
  clientToServerNonce?: Object | string | number | boolean | null;
  serverToClientNonce?: Object | string | number | boolean | null;
}

interface RejectedCounter {
  counter?: Object | string | number | boolean | null;
  reason?: Object | string | number | boolean | null;
}

export class CryptoVectorService {
  validateEd25519SignatureVector(input: string): CryptoVectorValidationResult {
    const vector = parseJson<Ed25519SignatureVector>(input);
    if (vector === null || vector.algorithm !== 'Ed25519') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'algorithm' };
    }
    const privateSeed = requireString(vector.privateSeed, 'privateSeed');
    if (!privateSeed.ok) {
      return privateSeed;
    }
    const publicKey = requireString(vector.publicKey, 'publicKey');
    if (!publicKey.ok) {
      return publicKey;
    }
    const signature = requireString(vector.signature, 'signature');
    if (!signature.ok) {
      return signature;
    }
    if (typeof vector.message !== 'string') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'message' };
    }
    return allOk([
      requireDecodedLength(privateSeed.value, 32, 'privateSeed'),
      requireDecodedLength(publicKey.value, 32, 'publicKey'),
      requireDecodedLength(signature.value, 64, 'signature')
    ]);
  }

  validateX25519SharedSecretVector(input: string): CryptoVectorValidationResult {
    const vector = parseJson<X25519SharedSecretVector>(input);
    if (vector === null || vector.algorithm !== 'X25519') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'algorithm' };
    }
    for (const field of ['alicePrivateKey', 'alicePublicKey', 'bobPrivateKey', 'bobPublicKey', 'sharedSecret']) {
      const value = requireString(getVectorField(vector, field), field);
      if (!value.ok) {
        return value;
      }
      const length = requireDecodedLength(value.value, 32, field);
      if (!length.ok) {
        return length;
      }
    }
    return { ok: true };
  }

  validateHkdfSha256Vector(input: string): CryptoVectorValidationResult {
    const vector = parseJson<HkdfSha256Vector>(input);
    if (vector === null || vector.algorithm !== 'HKDF-SHA-256') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'algorithm' };
    }
    if (typeof vector.length !== 'number' || !Number.isSafeInteger(vector.length) || vector.length <= 0) {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'length' };
    }
    const checks: CryptoVectorValidationResult[] = [];
    for (const field of ['ikm', 'salt', 'info', 'prk', 'okm']) {
      const value = requireString(getVectorField(vector, field), field);
      if (!value.ok) {
        return value;
      }
      checks.push(requireBase64Url(value.value, field));
    }
    const okm = requireString(vector.okm, 'okm');
    if (!okm.ok) {
      return okm;
    }
    checks.push(requireDecodedLength(okm.value, vector.length, 'okm'));
    return allOk(checks);
  }

  validateAes256GcmVector(input: string): CryptoVectorValidationResult {
    const vector = parseJson<AesGcmVector>(input);
    if (vector === null || vector.algorithm !== 'AES-256-GCM') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'algorithm' };
    }
    const checks: CryptoVectorValidationResult[] = [
      requireDecodedLength(requireStringValue(vector.key), 32, 'key'),
      requireDecodedLength(requireStringValue(vector.nonce), 12, 'nonce'),
      requireBase64Url(requireStringValue(vector.aad), 'aad'),
      requireBase64Url(requireStringValue(vector.plaintext), 'plaintext'),
      requireBase64Url(requireStringValue(vector.ciphertext), 'ciphertext'),
      requireDecodedLength(requireStringValue(vector.tag), 16, 'tag'),
      requireDecodedLength(requireStringValue(vector.tamperedTag), 16, 'tamperedTag')
    ];
    return allOk(checks);
  }

  validateSessionKeysVector(input: string): CryptoVectorValidationResult {
    const vector = parseJson<SessionKeysVector>(input);
    if (vector === null || vector.algorithm !== 'EggClip-Session-Keys-v1') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'algorithm' };
    }
    if (vector.clientToServerInfo !== 'EggClip v1 session key client-to-server' ||
      vector.serverToClientInfo !== 'EggClip v1 session key server-to-client') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'info' };
    }
    if (typeof vector.counter !== 'number' || !Number.isSafeInteger(vector.counter) || vector.counter < 0) {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'counter' };
    }
    const checks: CryptoVectorValidationResult[] = [
      requireDecodedLength(requireStringValue(vector.sharedSecret), 32, 'sharedSecret'),
      requireBase64Url(requireStringValue(vector.transcriptSalt), 'transcriptSalt'),
      requireDecodedLength(requireStringValue(vector.clientToServerKey), 32, 'clientToServerKey'),
      requireDecodedLength(requireStringValue(vector.serverToClientKey), 32, 'serverToClientKey'),
      requireDecodedLength(requireStringValue(vector.clientToServerNonce), 12, 'clientToServerNonce'),
      requireDecodedLength(requireStringValue(vector.serverToClientNonce), 12, 'serverToClientNonce')
    ];
    const shape = allOk(checks);
    if (!shape.ok) {
      return shape;
    }
    if (encodeBase64Url(sessionNonce(SessionDirection.CLIENT_TO_SERVER, vector.counter)) !== vector.clientToServerNonce) {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'clientToServerNonce' };
    }
    if (encodeBase64Url(sessionNonce(SessionDirection.SERVER_TO_CLIENT, vector.counter)) !== vector.serverToClientNonce) {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'serverToClientNonce' };
    }
    return { ok: true };
  }

  validateReplayCounterVector(input: string): CryptoVectorValidationResult {
    const vector = parseJson<ReplayCounterVector>(input);
    if (vector === null || vector.algorithm !== 'EggClip-Session-Counter-v1') {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'algorithm' };
    }
    if (!Array.isArray(vector.accepted) || !Array.isArray(vector.rejected)) {
      return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'counters' };
    }
    const guard = new SessionCounterGuard();
    for (const counter of vector.accepted) {
      if (!Number.isSafeInteger(counter) || counter < 0 || !guard.accept(counter)) {
        return { ok: false, error: CryptoVectorErrorCode.REPLAY, field: 'accepted' };
      }
    }
    for (const rejected of vector.rejected) {
      if (typeof rejected.counter !== 'number' || typeof rejected.reason !== 'string') {
        return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'rejected' };
      }
      if (guard.accept(rejected.counter)) {
        return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field: 'rejected.counter' };
      }
    }
    return { ok: true };
  }
}

export function sessionNonce(direction: SessionDirection, counter: number): Uint8Array {
  const nonce = new Uint8Array(12);
  if (direction === SessionDirection.CLIENT_TO_SERVER) {
    nonce[0] = 0x63;
    nonce[1] = 0x32;
    nonce[2] = 0x73;
  } else {
    nonce[0] = 0x73;
    nonce[1] = 0x32;
    nonce[2] = 0x63;
  }
  nonce[3] = 0x01;
  let remaining = Math.trunc(counter);
  for (let index = 11; index >= 4; index -= 1) {
    nonce[index] = remaining & 0xff;
    remaining = Math.floor(remaining / 256);
  }
  return nonce;
}

class SessionCounterGuard {
  private highestSeen: number = -1;
  private readonly seen: Set<number> = new Set<number>();

  accept(counter: number): boolean {
    if (this.seen.has(counter) || counter <= this.highestSeen) {
      return false;
    }
    this.seen.add(counter);
    this.highestSeen = counter;
    return true;
  }
}

interface StringFieldResult extends CryptoVectorValidationResult {
  value: string;
}

function parseJson<T>(input: string): T | null {
  try {
    const value = JSON.parse(input) as T;
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    return value;
  } catch (_) {
    return null;
  }
}

function getVectorField(vector: Object, field: string): Object | string | number | boolean | null | undefined {
  return (vector as Record<string, Object | string | number | boolean | null | undefined>)[field];
}

function requireString(value: Object | string | number | boolean | null | undefined, field: string): StringFieldResult {
  if (typeof value !== 'string') {
    return { ok: false, error: CryptoVectorErrorCode.INVALID_FIELD, field, value: '' };
  }
  return { ok: true, value };
}

function requireStringValue(value: Object | string | number | boolean | null | undefined): string {
  return typeof value === 'string' ? value : '#';
}

function requireBase64Url(value: string, field: string): CryptoVectorValidationResult {
  return decodeBase64Url(value) === null
    ? { ok: false, error: CryptoVectorErrorCode.INVALID_BASE64URL, field }
    : { ok: true };
}

function requireDecodedLength(value: string, expectedLength: number, field: string): CryptoVectorValidationResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return { ok: false, error: CryptoVectorErrorCode.INVALID_BASE64URL, field };
  }
  if (decoded.length !== expectedLength) {
    return { ok: false, error: CryptoVectorErrorCode.INVALID_LENGTH, field };
  }
  return { ok: true };
}

export function decodeBase64Url(value: string): Uint8Array | null {
  if (value.length % 4 === 1) {
    return null;
  }
  let buffer = 0;
  let bits = 0;
  const bytes: number[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const decoded = decodeBase64UrlChar(value.charCodeAt(index));
    if (decoded < 0) {
      return null;
    }
    buffer = (buffer << 6) | decoded;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 0xff);
    }
  }
  if (bits > 0 && (buffer & ((1 << bits) - 1)) !== 0) {
    return null;
  }
  return new Uint8Array(bytes);
}

export function encodeBase64Url(value: Uint8Array): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let output = '';
  let index = 0;
  while (index + 2 < value.length) {
    const triple = (value[index] << 16) | (value[index + 1] << 8) | value[index + 2];
    output += alphabet.charAt((triple >> 18) & 0x3f);
    output += alphabet.charAt((triple >> 12) & 0x3f);
    output += alphabet.charAt((triple >> 6) & 0x3f);
    output += alphabet.charAt(triple & 0x3f);
    index += 3;
  }
  const remaining = value.length - index;
  if (remaining === 1) {
    const single = value[index];
    output += alphabet.charAt((single >> 2) & 0x3f);
    output += alphabet.charAt((single << 4) & 0x3f);
  } else if (remaining === 2) {
    const pair = (value[index] << 8) | value[index + 1];
    output += alphabet.charAt((pair >> 10) & 0x3f);
    output += alphabet.charAt((pair >> 4) & 0x3f);
    output += alphabet.charAt((pair << 2) & 0x3f);
  }
  return output;
}

function decodeBase64UrlChar(code: number): number {
  if (code >= 65 && code <= 90) {
    return code - 65;
  }
  if (code >= 97 && code <= 122) {
    return code - 71;
  }
  if (code >= 48 && code <= 57) {
    return code + 4;
  }
  if (code === 45) {
    return 62;
  }
  if (code === 95) {
    return 63;
  }
  return -1;
}

function allOk(results: CryptoVectorValidationResult[]): CryptoVectorValidationResult {
  for (const result of results) {
    if (!result.ok) {
      return result;
    }
  }
  return { ok: true };
}
