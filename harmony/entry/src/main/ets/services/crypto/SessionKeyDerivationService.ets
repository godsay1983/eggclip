import {
  decodeBase64Url,
  encodeBase64Url,
  SessionDirection,
  sessionNonce
} from './CryptoVectorService';
import { sha256 } from './Sha256Service';

const SHA256_BYTES: number = 32;
const HMAC_SHA256_BLOCK_BYTES: number = 64;
const X25519_SHARED_SECRET_BYTES: number = 32;
const SESSION_KEY_BYTES: number = 32;
const CLIENT_TO_SERVER_INFO: string = 'EggClip v1 session key client-to-server';
const SERVER_TO_CLIENT_INFO: string = 'EggClip v1 session key server-to-client';

export enum SessionKeyDerivationError {
  INVALID_BASE64URL = 'invalidBase64url',
  INVALID_LENGTH = 'invalidLength',
  HKDF_FAILED = 'hkdfFailed'
}

export interface SessionKeyDerivationResult {
  ok: boolean;
  keys?: SessionKeys;
  error?: SessionKeyDerivationError;
  field?: string;
}

export interface SessionKeys {
  clientToServerKey: string;
  serverToClientKey: string;
}

export interface SessionNonceResult {
  ok: boolean;
  nonce?: string;
  error?: SessionKeyDerivationError;
  field?: string;
}

export class SessionKeyDerivationService {
  deriveSessionKeys(
    sharedSecretBase64Url: string,
    transcriptSaltBase64Url: string
  ): SessionKeyDerivationResult {
    const sharedSecret = decodeBase64Url(sharedSecretBase64Url);
    if (sharedSecret === null) {
      return failedDerivation(SessionKeyDerivationError.INVALID_BASE64URL, 'sharedSecret');
    }
    if (sharedSecret.length !== X25519_SHARED_SECRET_BYTES) {
      return failedDerivation(SessionKeyDerivationError.INVALID_LENGTH, 'sharedSecret');
    }
    const transcriptSalt = decodeBase64Url(transcriptSaltBase64Url);
    if (transcriptSalt === null) {
      return failedDerivation(SessionKeyDerivationError.INVALID_BASE64URL, 'transcriptSalt');
    }

    const clientToServer = hkdfSha256(sharedSecret, transcriptSalt, utf8Encode(CLIENT_TO_SERVER_INFO), SESSION_KEY_BYTES);
    const serverToClient = hkdfSha256(sharedSecret, transcriptSalt, utf8Encode(SERVER_TO_CLIENT_INFO), SESSION_KEY_BYTES);
    if (clientToServer === null || serverToClient === null) {
      return failedDerivation(SessionKeyDerivationError.HKDF_FAILED, 'sessionKey');
    }
    return {
      ok: true,
      keys: {
        clientToServerKey: encodeBase64Url(clientToServer),
        serverToClientKey: encodeBase64Url(serverToClient)
      }
    };
  }

  sessionNonceBase64Url(direction: SessionDirection, counter: number): SessionNonceResult {
    if (!Number.isSafeInteger(counter) || counter < 0) {
      return failedNonce(SessionKeyDerivationError.INVALID_LENGTH, 'counter');
    }
    return {
      ok: true,
      nonce: encodeBase64Url(sessionNonce(direction, counter))
    };
  }
}

function hkdfSha256(
  ikm: Uint8Array,
  salt: Uint8Array,
  info: Uint8Array,
  outputLength: number
): Uint8Array | null {
  if (!Number.isSafeInteger(outputLength) || outputLength <= 0 || outputLength > 255 * SHA256_BYTES) {
    return null;
  }
  const prk = hmacSha256(salt, ikm);
  const output = new Uint8Array(outputLength);
  let previous = new Uint8Array(0);
  let offset = 0;
  const blocks = Math.ceil(outputLength / SHA256_BYTES);

  for (let blockIndex = 1; blockIndex <= blocks; blockIndex += 1) {
    const blockInput = new Uint8Array(previous.length + info.length + 1);
    blockInput.set(previous, 0);
    blockInput.set(info, previous.length);
    blockInput[blockInput.length - 1] = blockIndex;
    previous = hmacSha256(prk, blockInput);
    const bytesToCopy = Math.min(previous.length, outputLength - offset);
    output.set(previous.subarray(0, bytesToCopy), offset);
    offset += bytesToCopy;
  }

  return output;
}

function hmacSha256(key: Uint8Array, message: Uint8Array): Uint8Array {
  let normalizedKey = key;
  if (normalizedKey.length > HMAC_SHA256_BLOCK_BYTES) {
    normalizedKey = sha256(normalizedKey);
  }
  const keyBlock = new Uint8Array(HMAC_SHA256_BLOCK_BYTES);
  keyBlock.set(normalizedKey);
  const outerPad = new Uint8Array(HMAC_SHA256_BLOCK_BYTES);
  const innerPad = new Uint8Array(HMAC_SHA256_BLOCK_BYTES);
  for (let index = 0; index < HMAC_SHA256_BLOCK_BYTES; index += 1) {
    outerPad[index] = keyBlock[index] ^ 0x5c;
    innerPad[index] = keyBlock[index] ^ 0x36;
  }

  const innerInput = new Uint8Array(innerPad.length + message.length);
  innerInput.set(innerPad, 0);
  innerInput.set(message, innerPad.length);
  const innerHash = sha256(innerInput);

  const outerInput = new Uint8Array(outerPad.length + innerHash.length);
  outerInput.set(outerPad, 0);
  outerInput.set(innerHash, outerPad.length);
  return sha256(outerInput);
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

function failedDerivation(
  error: SessionKeyDerivationError,
  field: string
): SessionKeyDerivationResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedNonce(
  error: SessionKeyDerivationError,
  field: string
): SessionNonceResult {
  return {
    ok: false,
    error,
    field
  };
}
