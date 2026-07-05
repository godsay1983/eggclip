import cryptoFramework from '@ohos.security.cryptoFramework';
import {
  decodeBase64Url,
  encodeBase64Url
} from './CryptoVectorService';

const X25519_KEY_BYTES: number = 32;
const X25519_ALGORITHM: string = 'X25519';

export enum X25519KeyAgreementError {
  INVALID_BASE64URL = 'invalidBase64url',
  INVALID_LENGTH = 'invalidLength',
  PLATFORM_CRYPTO_FAILED = 'platformCryptoFailed'
}

export interface X25519KeyPairResult {
  ok: boolean;
  privateKey?: string;
  publicKey?: string;
  error?: X25519KeyAgreementError;
  field?: string;
}

export interface X25519SharedSecretResult {
  ok: boolean;
  sharedSecret?: string;
  error?: X25519KeyAgreementError;
  field?: string;
}

export class X25519KeyAgreementService {
  generateEphemeralKeyPair(): X25519KeyPairResult {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator(X25519_ALGORITHM);
      const keyPair = generator.generateKeyPairSync();
      const privateValue = keyPair.priKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.X25519_SK_BN);
      const publicValue = keyPair.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.X25519_PK_BN);
      if (typeof privateValue !== 'bigint' || typeof publicValue !== 'bigint') {
        return failedKeyPair(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED, 'keyPair');
      }
      const privateKey = bigIntToLittleEndianBytes(privateValue, X25519_KEY_BYTES);
      const publicKey = bigIntToLittleEndianBytes(publicValue, X25519_KEY_BYTES);
      keyPair.priKey.clearMem();
      return {
        ok: true,
        privateKey: encodeBase64Url(privateKey),
        publicKey: encodeBase64Url(publicKey)
      };
    } catch (_) {
      return failedKeyPair(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED, 'keyPair');
    }
  }

  deriveSharedSecret(
    privateKeyBase64Url: string,
    peerPublicKeyBase64Url: string
  ): X25519SharedSecretResult {
    const privateKey = decodeRequired(privateKeyBase64Url, 'privateKey');
    if (!privateKey.ok || privateKey.value === undefined) {
      return failedSecret(privateKey.error, privateKey.field);
    }
    const peerPublicKey = decodeRequired(peerPublicKeyBase64Url, 'peerPublicKey');
    if (!peerPublicKey.ok || peerPublicKey.value === undefined) {
      return failedSecret(peerPublicKey.error, peerPublicKey.field);
    }

    try {
      const privateSpec: cryptoFramework.X25519PriKeySpec = {
        algName: X25519_ALGORITHM,
        specType: cryptoFramework.AsyKeySpecType.PRIVATE_KEY_SPEC,
        sk: littleEndianBytesToBigInt(privateKey.value)
      };
      const publicSpec: cryptoFramework.X25519PubKeySpec = {
        algName: X25519_ALGORITHM,
        specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC,
        pk: littleEndianBytesToBigInt(peerPublicKey.value)
      };
      const privateKeyObject = cryptoFramework.createAsyKeyGeneratorBySpec(privateSpec).generatePriKeySync();
      const publicKeyObject = cryptoFramework.createAsyKeyGeneratorBySpec(publicSpec).generatePubKeySync();
      const agreement = cryptoFramework.createKeyAgreement(X25519_ALGORITHM);
      const secret = agreement.generateSecretSync(privateKeyObject, publicKeyObject).data;
      privateKeyObject.clearMem();
      if (secret.length !== X25519_KEY_BYTES) {
        return failedSecret(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED, 'sharedSecret');
      }
      return {
        ok: true,
        sharedSecret: encodeBase64Url(secret)
      };
    } catch (_) {
      return failedSecret(X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED, 'keyAgreement');
    }
  }
}

interface DecodeResult {
  ok: boolean;
  value?: Uint8Array;
  error: X25519KeyAgreementError;
  field: string;
}

function decodeRequired(value: string, field: string): DecodeResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return decodeFailed(X25519KeyAgreementError.INVALID_BASE64URL, field);
  }
  if (decoded.length !== X25519_KEY_BYTES) {
    return decodeFailed(X25519KeyAgreementError.INVALID_LENGTH, field);
  }
  return {
    ok: true,
    value: decoded,
    error: X25519KeyAgreementError.PLATFORM_CRYPTO_FAILED,
    field
  };
}

function decodeFailed(error: X25519KeyAgreementError, field: string): DecodeResult {
  return {
    ok: false,
    error,
    field
  };
}

function littleEndianBytesToBigInt(bytes: Uint8Array): bigint {
  let result = BigInt(0);
  for (let index = bytes.length - 1; index >= 0; index -= 1) {
    result = (result << BigInt(8)) + BigInt(bytes[index]);
  }
  return result;
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

function failedKeyPair(
  error: X25519KeyAgreementError,
  field: string
): X25519KeyPairResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedSecret(
  error: X25519KeyAgreementError,
  field: string
): X25519SharedSecretResult {
  return {
    ok: false,
    error,
    field
  };
}
