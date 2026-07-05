import cryptoFramework from '@ohos.security.cryptoFramework';
import {
  decodeBase64Url,
  encodeBase64Url
} from './CryptoVectorService';
import {
  Ed25519SignatureError,
  Ed25519SignatureService
} from './Ed25519SignatureService';

const ED25519_KEY_BYTES: number = 32;
const ED25519_ALGORITHM: string = 'Ed25519';

export enum Ed25519IdentityError {
  INVALID_BASE64URL = 'invalidBase64url',
  INVALID_LENGTH = 'invalidLength',
  PLATFORM_CRYPTO_FAILED = 'platformCryptoFailed',
  SIGN_FAILED = 'signFailed'
}

export interface Ed25519IdentityMaterialResult {
  ok: boolean;
  identityPrivateKey?: string;
  identityPublicKey?: string;
  error?: Ed25519IdentityError;
  field?: string;
}

export interface Ed25519IdentitySignatureResult {
  ok: boolean;
  signature?: string;
  error?: Ed25519IdentityError;
  signatureError?: Ed25519SignatureError;
  field?: string;
}

export class Ed25519IdentityService {
  private readonly signatureService: Ed25519SignatureService = new Ed25519SignatureService();

  generateIdentityMaterial(): Ed25519IdentityMaterialResult {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator(ED25519_ALGORITHM);
      const keyPair = generator.generateKeyPairSync();
      const privateValue = keyPair.priKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ED25519_SK_BN);
      const publicValue = keyPair.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.ED25519_PK_BN);
      if (typeof privateValue !== 'bigint' || typeof publicValue !== 'bigint') {
        return failedMaterial(Ed25519IdentityError.PLATFORM_CRYPTO_FAILED, 'identityKeyPair');
      }

      const identityPrivateKey = bigIntToLittleEndianBytes(privateValue, ED25519_KEY_BYTES);
      const identityPublicKey = bigIntToLittleEndianBytes(publicValue, ED25519_KEY_BYTES);
      keyPair.priKey.clearMem();
      return {
        ok: true,
        identityPrivateKey: encodeBase64Url(identityPrivateKey),
        identityPublicKey: encodeBase64Url(identityPublicKey)
      };
    } catch (_) {
      return failedMaterial(Ed25519IdentityError.PLATFORM_CRYPTO_FAILED, 'identityKeyPair');
    }
  }

  signAuthTranscript(
    identityPrivateKeyBase64Url: string,
    canonicalTranscript: string
  ): Ed25519IdentitySignatureResult {
    const decoded = decodeRequired(identityPrivateKeyBase64Url, 'identityPrivateKey');
    if (!decoded.ok) {
      return failedSignature(decoded.error, decoded.field);
    }

    const signed = this.signatureService.signMessage(identityPrivateKeyBase64Url, canonicalTranscript);
    if (!signed.ok || signed.signature === undefined) {
      return {
        ok: false,
        error: Ed25519IdentityError.SIGN_FAILED,
        signatureError: signed.error,
        field: signed.field
      };
    }

    return {
      ok: true,
      signature: signed.signature
    };
  }
}

interface DecodeResult {
  ok: boolean;
  error: Ed25519IdentityError;
  field: string;
}

function decodeRequired(value: string, field: string): DecodeResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return decodeFailed(Ed25519IdentityError.INVALID_BASE64URL, field);
  }
  if (decoded.length !== ED25519_KEY_BYTES) {
    return decodeFailed(Ed25519IdentityError.INVALID_LENGTH, field);
  }
  return {
    ok: true,
    error: Ed25519IdentityError.PLATFORM_CRYPTO_FAILED,
    field
  };
}

function decodeFailed(error: Ed25519IdentityError, field: string): DecodeResult {
  return {
    ok: false,
    error,
    field
  };
}

function bigIntToLittleEndianBytes(value: bigint, length: number): Uint8Array {
  const output = new Uint8Array(length);
  let remaining = value;
  for (let index = 0; index < length; index += 1) {
    output[index] = Number(remaining & BigInt(0xff));
    remaining = remaining >> BigInt(8);
  }
  return output;
}

function failedMaterial(
  error: Ed25519IdentityError,
  field: string
): Ed25519IdentityMaterialResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedSignature(
  error: Ed25519IdentityError,
  field: string
): Ed25519IdentitySignatureResult {
  return {
    ok: false,
    error,
    field
  };
}
