import huks from '@ohos.security.huks';
import { encodeBase64Url } from './CryptoVectorService';

const ED25519_KEY_BYTES: number = 32;
const ED25519_SIGNATURE_BYTES: number = 64;
const LOCAL_IDENTITY_REF_PREFIX: string = 'huks://eggclip/local-identity/ed25519/';
const LOCAL_IDENTITY_ALIAS_PREFIX: string = 'eggclip.local-identity.ed25519.';

export enum Ed25519HuksIdentityError {
  INVALID_KEY_REF = 'invalidKeyRef',
  INVALID_ALIAS_SLOT = 'invalidAliasSlot',
  INVALID_PUBLIC_KEY = 'invalidPublicKey',
  INVALID_SIGNATURE = 'invalidSignature',
  PLATFORM_CRYPTO_FAILED = 'platformCryptoFailed'
}

export interface Ed25519HuksIdentityMaterialResult {
  ok: boolean;
  identityPublicKey?: string;
  identityPrivateKeyRef?: string;
  error?: Ed25519HuksIdentityError;
  field?: string;
}

export interface Ed25519HuksSignatureResult {
  ok: boolean;
  signature?: string;
  error?: Ed25519HuksIdentityError;
  field?: string;
}

export interface Ed25519HuksKeyRefResult {
  ok: boolean;
  identityPrivateKeyRef?: string;
  huksAlias?: string;
  error?: Ed25519HuksIdentityError;
  field?: string;
}

export class Ed25519HuksIdentityService {
  buildLocalIdentityPrivateKeyRef(aliasSlot: string = 'v1'): Ed25519HuksKeyRefResult {
    if (!isValidAliasSlot(aliasSlot)) {
      return failedKeyRef(Ed25519HuksIdentityError.INVALID_ALIAS_SLOT, 'aliasSlot');
    }
    return {
      ok: true,
      identityPrivateKeyRef: `${LOCAL_IDENTITY_REF_PREFIX}${aliasSlot}`
    };
  }

  huksAliasFromRef(identityPrivateKeyRef: string): Ed25519HuksKeyRefResult {
    if (!identityPrivateKeyRef.startsWith(LOCAL_IDENTITY_REF_PREFIX)) {
      return failedKeyRef(Ed25519HuksIdentityError.INVALID_KEY_REF, 'identityPrivateKeyRef');
    }
    const slot = identityPrivateKeyRef.substring(LOCAL_IDENTITY_REF_PREFIX.length);
    if (!isValidAliasSlot(slot)) {
      return failedKeyRef(Ed25519HuksIdentityError.INVALID_KEY_REF, 'identityPrivateKeyRef');
    }
    return {
      ok: true,
      huksAlias: `${LOCAL_IDENTITY_ALIAS_PREFIX}${slot}`
    };
  }

  generateOptions(): huks.HuksOptions {
    return {
      properties: [
        {
          tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
          value: huks.HuksKeyAlg.HUKS_ALG_ED25519
        },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_VERIFY
        },
        {
          tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
          value: huks.HuksKeySize.HUKS_CURVE25519_KEY_SIZE_256
        },
        {
          tag: huks.HuksTag.HUKS_TAG_DIGEST,
          value: huks.HuksKeyDigest.HUKS_DIGEST_NONE
        },
        {
          tag: huks.HuksTag.HUKS_TAG_KEY_OVERRIDE,
          value: false
        }
      ]
    };
  }

  signOptions(message: string): huks.HuksOptions {
    return {
      properties: [
        {
          tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
          value: huks.HuksKeyAlg.HUKS_ALG_ED25519
        },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN
        },
        {
          tag: huks.HuksTag.HUKS_TAG_DIGEST,
          value: huks.HuksKeyDigest.HUKS_DIGEST_NONE
        }
      ],
      inData: utf8Encode(message)
    };
  }

  async generateOrLoadIdentity(identityPrivateKeyRef: string): Promise<Ed25519HuksIdentityMaterialResult> {
    const alias = this.huksAliasFromRef(identityPrivateKeyRef);
    if (!alias.ok || alias.huksAlias === undefined) {
      return failedMaterial(alias.error ?? Ed25519HuksIdentityError.INVALID_KEY_REF, alias.field ?? 'identityPrivateKeyRef');
    }

    try {
      await huks.generateKeyItem(alias.huksAlias, this.generateOptions());
    } catch (_) {
      const exportedExisting = await this.exportPublicKey(alias.huksAlias, identityPrivateKeyRef);
      if (exportedExisting.ok) {
        return exportedExisting;
      }
      return failedMaterial(Ed25519HuksIdentityError.PLATFORM_CRYPTO_FAILED, 'generateKeyItem');
    }

    return this.exportPublicKey(alias.huksAlias, identityPrivateKeyRef);
  }

  async signAuthTranscriptWithRef(
    identityPrivateKeyRef: string,
    canonicalTranscript: string
  ): Promise<Ed25519HuksSignatureResult> {
    const alias = this.huksAliasFromRef(identityPrivateKeyRef);
    if (!alias.ok || alias.huksAlias === undefined) {
      return failedSignature(alias.error ?? Ed25519HuksIdentityError.INVALID_KEY_REF, alias.field ?? 'identityPrivateKeyRef');
    }

    try {
      const options = this.signOptions(canonicalTranscript);
      const session = await huks.initSession(alias.huksAlias, options);
      const signed = await huks.finishSession(session.handle, options);
      const signature = signed.outData;
      if (signature === undefined || signature.length !== ED25519_SIGNATURE_BYTES) {
        return failedSignature(Ed25519HuksIdentityError.INVALID_SIGNATURE, 'signature');
      }
      return {
        ok: true,
        signature: encodeBase64Url(signature)
      };
    } catch (_) {
      return failedSignature(Ed25519HuksIdentityError.PLATFORM_CRYPTO_FAILED, 'signAuthTranscript');
    }
  }

  private async exportPublicKey(
    huksAlias: string,
    identityPrivateKeyRef: string
  ): Promise<Ed25519HuksIdentityMaterialResult> {
    try {
      const exported = await huks.exportKeyItem(huksAlias, {});
      const publicKey = exported.outData;
      if (publicKey === undefined || publicKey.length !== ED25519_KEY_BYTES) {
        return failedMaterial(Ed25519HuksIdentityError.INVALID_PUBLIC_KEY, 'identityPublicKey');
      }
      return {
        ok: true,
        identityPublicKey: encodeBase64Url(publicKey),
        identityPrivateKeyRef
      };
    } catch (_) {
      return failedMaterial(Ed25519HuksIdentityError.PLATFORM_CRYPTO_FAILED, 'exportKeyItem');
    }
  }
}

function isValidAliasSlot(value: string): boolean {
  return /^[A-Za-z0-9._-]{1,64}$/.test(value);
}

function failedMaterial(
  error: Ed25519HuksIdentityError,
  field: string
): Ed25519HuksIdentityMaterialResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedSignature(
  error: Ed25519HuksIdentityError,
  field: string
): Ed25519HuksSignatureResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedKeyRef(
  error: Ed25519HuksIdentityError,
  field: string
): Ed25519HuksKeyRefResult {
  return {
    ok: false,
    error,
    field
  };
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
