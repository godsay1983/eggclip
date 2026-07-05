import cryptoFramework from '@ohos.security.cryptoFramework';
import {
  decodeBase64Url,
  encodeBase64Url
} from './CryptoVectorService';

const AES_256_KEY_BYTES: number = 32;
const AES_GCM_NONCE_BYTES: number = 12;
const AES_GCM_TAG_BYTES: number = 16;
const AES_GCM_TRANSFORMS: string[] = [
  'AES256|GCM|NoPadding',
  'AES256|GCM|PKCS7',
  'AES|GCM|NoPadding'
];

export enum AesGcmCryptoError {
  INVALID_BASE64URL = 'invalidBase64url',
  INVALID_LENGTH = 'invalidLength',
  PLATFORM_CRYPTO_FAILED = 'platformCryptoFailed'
}

export interface AesGcmEncryptResult {
  ok: boolean;
  body?: string;
  tag?: string;
  error?: AesGcmCryptoError;
  field?: string;
}

export interface AesGcmDecryptResult {
  ok: boolean;
  plaintext?: string;
  error?: AesGcmCryptoError;
  field?: string;
}

export class AesGcmCryptoService {
  encryptBase64Url(
    keyBase64Url: string,
    nonceBase64Url: string,
    aadBase64Url: string,
    plaintextBase64Url: string
  ): AesGcmEncryptResult {
    const key = decodeRequired(keyBase64Url, AES_256_KEY_BYTES, 'key');
    if (!key.ok || key.value === undefined) {
      return failedEncrypt(key.error, key.field);
    }
    const nonce = decodeRequired(nonceBase64Url, AES_GCM_NONCE_BYTES, 'nonce');
    if (!nonce.ok || nonce.value === undefined) {
      return failedEncrypt(nonce.error, nonce.field);
    }
    const aad = decodeOptional(aadBase64Url, 'aad');
    if (!aad.ok || aad.value === undefined) {
      return failedEncrypt(aad.error, aad.field);
    }
    const plaintext = decodeOptional(plaintextBase64Url, 'plaintext');
    if (!plaintext.ok || plaintext.value === undefined) {
      return failedEncrypt(plaintext.error, plaintext.field);
    }

    for (const transform of AES_GCM_TRANSFORMS) {
      const encrypted = encryptWithTransform(transform, key.value, nonce.value, aad.value, plaintext.value);
      if (encrypted !== null) {
        return {
          ok: true,
          body: encodeBase64Url(encrypted.body),
          tag: encodeBase64Url(encrypted.tag)
        };
      }
    }
    return failedEncrypt(AesGcmCryptoError.PLATFORM_CRYPTO_FAILED, 'cipher');
  }

  decryptBase64Url(
    keyBase64Url: string,
    nonceBase64Url: string,
    aadBase64Url: string,
    bodyBase64Url: string,
    tagBase64Url: string
  ): AesGcmDecryptResult {
    const key = decodeRequired(keyBase64Url, AES_256_KEY_BYTES, 'key');
    if (!key.ok || key.value === undefined) {
      return failedDecrypt(key.error, key.field);
    }
    const nonce = decodeRequired(nonceBase64Url, AES_GCM_NONCE_BYTES, 'nonce');
    if (!nonce.ok || nonce.value === undefined) {
      return failedDecrypt(nonce.error, nonce.field);
    }
    const aad = decodeOptional(aadBase64Url, 'aad');
    if (!aad.ok || aad.value === undefined) {
      return failedDecrypt(aad.error, aad.field);
    }
    const body = decodeOptional(bodyBase64Url, 'body');
    if (!body.ok || body.value === undefined) {
      return failedDecrypt(body.error, body.field);
    }
    const tag = decodeRequired(tagBase64Url, AES_GCM_TAG_BYTES, 'tag');
    if (!tag.ok || tag.value === undefined) {
      return failedDecrypt(tag.error, tag.field);
    }

    for (const transform of AES_GCM_TRANSFORMS) {
      const plaintext = decryptWithTransform(transform, key.value, nonce.value, aad.value, body.value, tag.value);
      if (plaintext !== null) {
        return {
          ok: true,
          plaintext: encodeBase64Url(plaintext)
        };
      }
    }
    return failedDecrypt(AesGcmCryptoError.PLATFORM_CRYPTO_FAILED, 'cipher');
  }
}

interface DecodeBytesResult {
  ok: boolean;
  value?: Uint8Array;
  error: AesGcmCryptoError;
  field: string;
}

interface AesGcmEncryptedBytes {
  body: Uint8Array;
  tag: Uint8Array;
}

function encryptWithTransform(
  transform: string,
  key: Uint8Array,
  nonce: Uint8Array,
  aad: Uint8Array,
  plaintext: Uint8Array
): AesGcmEncryptedBytes | null {
  try {
    const symKey = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: key });
    const params: cryptoFramework.GcmParamsSpec = gcmParams(nonce, aad, new Uint8Array(0));
    const cipher = cryptoFramework.createCipher(transform);
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
    const output = cipher.doFinalSync({ data: plaintext }).data;
    const paramsTag = params.authTag.data;
    if (paramsTag.length === AES_GCM_TAG_BYTES) {
      return {
        body: output,
        tag: paramsTag
      };
    }
    if (output.length >= AES_GCM_TAG_BYTES) {
      return {
        body: output.subarray(0, output.length - AES_GCM_TAG_BYTES),
        tag: output.subarray(output.length - AES_GCM_TAG_BYTES)
      };
    }
  } catch (_) {
    return null;
  }
  return null;
}

function decryptWithTransform(
  transform: string,
  key: Uint8Array,
  nonce: Uint8Array,
  aad: Uint8Array,
  body: Uint8Array,
  tag: Uint8Array
): Uint8Array | null {
  try {
    const symKey = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: key });
    const params = gcmParams(nonce, aad, tag);
    const cipher = cryptoFramework.createCipher(transform);
    cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    return cipher.doFinalSync({ data: body }).data;
  } catch (_) {
    return null;
  }
}

function gcmParams(nonce: Uint8Array, aad: Uint8Array, tag: Uint8Array): cryptoFramework.GcmParamsSpec {
  return {
    algName: 'GcmParamsSpec',
    iv: { data: nonce },
    aad: { data: aad },
    authTag: { data: tag }
  };
}

function decodeRequired(value: string, expectedBytes: number, field: string): DecodeBytesResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return decodeFailed(AesGcmCryptoError.INVALID_BASE64URL, field);
  }
  if (decoded.length !== expectedBytes) {
    return decodeFailed(AesGcmCryptoError.INVALID_LENGTH, field);
  }
  return decodeOk(decoded, field);
}

function decodeOptional(value: string, field: string): DecodeBytesResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return decodeFailed(AesGcmCryptoError.INVALID_BASE64URL, field);
  }
  return decodeOk(decoded, field);
}

function decodeOk(value: Uint8Array, field: string): DecodeBytesResult {
  return {
    ok: true,
    value,
    error: AesGcmCryptoError.PLATFORM_CRYPTO_FAILED,
    field
  };
}

function decodeFailed(error: AesGcmCryptoError, field: string): DecodeBytesResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedEncrypt(error: AesGcmCryptoError, field: string): AesGcmEncryptResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedDecrypt(error: AesGcmCryptoError, field: string): AesGcmDecryptResult {
  return {
    ok: false,
    error,
    field
  };
}
