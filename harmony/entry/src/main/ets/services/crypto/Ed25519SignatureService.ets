import cryptoFramework from '@ohos.security.cryptoFramework';
import {
  decodeBase64Url,
  encodeBase64Url
} from './CryptoVectorService';

const ED25519_KEY_BYTES: number = 32;
const ED25519_SIGNATURE_BYTES: number = 64;

export enum Ed25519SignatureError {
  INVALID_JSON = 'invalidJson',
  INVALID_FIELD = 'invalidField',
  INVALID_BASE64URL = 'invalidBase64url',
  INVALID_LENGTH = 'invalidLength',
  PLATFORM_CRYPTO_FAILED = 'platformCryptoFailed',
  SIGNATURE_MISMATCH = 'signatureMismatch'
}

export interface Ed25519SignatureResult {
  ok: boolean;
  signature?: string;
  error?: Ed25519SignatureError;
  field?: string;
}

interface Ed25519SignatureVector {
  algorithm?: Object | string | number | boolean | null;
  privateSeed?: Object | string | number | boolean | null;
  publicKey?: Object | string | number | boolean | null;
  message?: Object | string | number | boolean | null;
  signature?: Object | string | number | boolean | null;
}

enum BigIntEndian {
  BIG,
  LITTLE
}

interface Ed25519SignAttempt {
  algName: string;
  endian: BigIntEndian;
}

export class Ed25519SignatureService {
  signMessage(privateSeedBase64Url: string, message: string): Ed25519SignatureResult {
    const privateSeed = decodeRequired(privateSeedBase64Url, 'privateSeed');
    if (!privateSeed.ok || privateSeed.value === undefined) {
      return failed(privateSeed.error, privateSeed.field);
    }

    const attempts: Ed25519SignAttempt[] = [
      { algName: 'Ed25519', endian: BigIntEndian.LITTLE },
      { algName: 'Ed25519', endian: BigIntEndian.BIG },
      { algName: 'ED25519', endian: BigIntEndian.LITTLE },
      { algName: 'ED25519', endian: BigIntEndian.BIG }
    ];

    for (const attempt of attempts) {
      const signed = this.signWithSpec(attempt.algName, attempt.endian, privateSeed.value, message);
      if (signed !== null) {
        return {
          ok: true,
          signature: encodeBase64Url(signed)
        };
      }
    }

    return failed(Ed25519SignatureError.PLATFORM_CRYPTO_FAILED, 'privateSeed');
  }

  signVector(input: string): Ed25519SignatureResult {
    const vector = parseJson<Ed25519SignatureVector>(input);
    if (vector === null || vector.algorithm !== 'Ed25519') {
      return failed(Ed25519SignatureError.INVALID_FIELD, 'algorithm');
    }
    if (typeof vector.privateSeed !== 'string') {
      return failed(Ed25519SignatureError.INVALID_FIELD, 'privateSeed');
    }
    if (typeof vector.message !== 'string') {
      return failed(Ed25519SignatureError.INVALID_FIELD, 'message');
    }
    if (typeof vector.signature !== 'string') {
      return failed(Ed25519SignatureError.INVALID_FIELD, 'signature');
    }

    const signed = this.signMessage(vector.privateSeed, vector.message);
    if (!signed.ok || signed.signature === undefined) {
      return signed;
    }
    if (signed.signature !== vector.signature) {
      return failed(Ed25519SignatureError.SIGNATURE_MISMATCH, 'signature');
    }
    return signed;
  }

  private signWithSpec(
    algName: string,
    endian: BigIntEndian,
    privateSeed: Uint8Array,
    message: string
  ): Uint8Array | null {
    try {
      const privateSpec: cryptoFramework.ED25519PriKeySpec = {
        algName,
        specType: cryptoFramework.AsyKeySpecType.PRIVATE_KEY_SPEC,
        sk: bytesToBigInt(privateSeed, endian)
      };
      const privateKey = cryptoFramework.createAsyKeyGeneratorBySpec(privateSpec).generatePriKeySync();
      const signer = cryptoFramework.createSign(algName);
      signer.initSync(privateKey);
      const signature = signer.signSync({ data: utf8Encode(message) }).data;
      privateKey.clearMem();
      if (signature.length !== ED25519_SIGNATURE_BYTES) {
        return null;
      }
      return signature;
    } catch (_) {
      return null;
    }
  }
}

interface DecodeResult {
  ok: boolean;
  value?: Uint8Array;
  error: Ed25519SignatureError;
  field: string;
}

function decodeRequired(value: string, field: string): DecodeResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return decodeFailed(Ed25519SignatureError.INVALID_BASE64URL, field);
  }
  if (decoded.length !== ED25519_KEY_BYTES) {
    return decodeFailed(Ed25519SignatureError.INVALID_LENGTH, field);
  }
  return {
    ok: true,
    value: decoded,
    error: Ed25519SignatureError.PLATFORM_CRYPTO_FAILED,
    field
  };
}

function decodeFailed(error: Ed25519SignatureError, field: string): DecodeResult {
  return {
    ok: false,
    error,
    field
  };
}

function failed(error: Ed25519SignatureError, field: string): Ed25519SignatureResult {
  return {
    ok: false,
    error,
    field
  };
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

function bytesToBigInt(bytes: Uint8Array, endian: BigIntEndian): bigint {
  let result = BigInt(0);
  if (endian === BigIntEndian.BIG) {
    for (let index = 0; index < bytes.length; index += 1) {
      result = (result << BigInt(8)) + BigInt(bytes[index]);
    }
    return result;
  }

  for (let index = bytes.length - 1; index >= 0; index -= 1) {
    result = (result << BigInt(8)) + BigInt(bytes[index]);
  }
  return result;
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
    } else if (
      code >= 0xd800 &&
      code <= 0xdbff &&
      index + 1 < value.length &&
      value.charCodeAt(index + 1) >= 0xdc00 &&
      value.charCodeAt(index + 1) <= 0xdfff
    ) {
      const next = value.charCodeAt(index + 1);
      const scalar = 0x10000 + (((code - 0xd800) << 10) | (next - 0xdc00));
      bytes.push(0xf0 | (scalar >> 18));
      bytes.push(0x80 | ((scalar >> 12) & 0x3f));
      bytes.push(0x80 | ((scalar >> 6) & 0x3f));
      bytes.push(0x80 | (scalar & 0x3f));
      index += 1;
    } else {
      bytes.push(0xe0 | (code >> 12));
      bytes.push(0x80 | ((code >> 6) & 0x3f));
      bytes.push(0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(bytes);
}
