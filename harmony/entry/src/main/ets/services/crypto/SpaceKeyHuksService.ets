import huks from '@ohos.security.huks';
import {
  decodeBase64Url,
  encodeBase64Url
} from './CryptoVectorService';
import { SPACE_KEY_BYTES } from './SpaceKeyReferenceService';

const SPACE_KEY_REF_PREFIX: string = 'huks://eggclip/space-key/';
const SPACE_KEY_ALIAS_PREFIX: string = 'eggclip.space-key.';
const AES_GCM_NONCE_BYTES: number = 12;
const AES_GCM_TAG_BYTES: number = 16;
const AES_GCM_TAG_BITS: number = 128;
const AES_GCM_TAG_LENGTH_CANDIDATES: number[] = [AES_GCM_TAG_BITS, AES_GCM_TAG_BYTES];

export enum SpaceKeyHuksError {
  INVALID_KEY_REF = 'invalidKeyRef',
  INVALID_KEY = 'invalidKey',
  INVALID_BASE64URL = 'invalidBase64url',
  INVALID_LENGTH = 'invalidLength',
  PLATFORM_CRYPTO_FAILED = 'platformCryptoFailed'
}

export interface SpaceKeyHuksImportResult {
  ok: boolean;
  encryptedSpaceKeyRef: string;
  huksAlias?: string;
  error?: SpaceKeyHuksError;
  field?: string;
}

export interface SpaceKeySecureImporter {
  importSpaceKey(encryptedSpaceKeyRef: string, key: Uint8Array): Promise<SpaceKeyHuksImportResult>;
}

export interface SpaceKeyHuksEncryptResult {
  ok: boolean;
  body?: string;
  tag?: string;
  error?: SpaceKeyHuksError;
  field?: string;
}

export interface SpaceKeyHuksDecryptResult {
  ok: boolean;
  plaintext?: string;
  error?: SpaceKeyHuksError;
  field?: string;
}

export class SpaceKeyHuksService implements SpaceKeySecureImporter {
  huksAliasFromRef(encryptedSpaceKeyRef: string): SpaceKeyHuksImportResult {
    if (!encryptedSpaceKeyRef.startsWith(SPACE_KEY_REF_PREFIX)) {
      return failed(SpaceKeyHuksError.INVALID_KEY_REF, 'encryptedSpaceKeyRef');
    }
    const suffix = encryptedSpaceKeyRef.substring(SPACE_KEY_REF_PREFIX.length);
    const match = /^([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\/v([1-9][0-9]{0,4})$/i.exec(suffix);
    if (match === null) {
      return failed(SpaceKeyHuksError.INVALID_KEY_REF, 'encryptedSpaceKeyRef');
    }
    const version = Number(match[2]);
    if (!Number.isSafeInteger(version) || version <= 0 || version > 0xffff) {
      return failed(SpaceKeyHuksError.INVALID_KEY_REF, 'encryptedSpaceKeyRef');
    }
    return {
      ok: true,
      encryptedSpaceKeyRef,
      huksAlias: `${SPACE_KEY_ALIAS_PREFIX}${match[1].toLowerCase()}.v${version}`
    };
  }

  importOptions(key: Uint8Array): huks.HuksOptions {
    return {
      properties: [
        {
          tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
          value: huks.HuksKeyAlg.HUKS_ALG_AES
        },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
        },
        {
          tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
          value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
        },
        {
          tag: huks.HuksTag.HUKS_TAG_PADDING,
          value: huks.HuksKeyPadding.HUKS_PADDING_NONE
        },
        {
          tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
          value: huks.HuksCipherMode.HUKS_MODE_GCM
        },
        {
          tag: huks.HuksTag.HUKS_TAG_KEY_OVERRIDE,
          value: false
        }
      ],
      inData: key
    };
  }

  operationOptions(
    purpose: number,
    nonce: Uint8Array,
    aad: Uint8Array,
    tag?: Uint8Array,
    tagLength: number = AES_GCM_TAG_BITS
  ): huks.HuksOptions {
    const properties: huks.HuksParam[] = [
      {
        tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
        value: huks.HuksKeyAlg.HUKS_ALG_AES
      },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: purpose
      },
      {
        tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
        value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
      },
      {
        tag: huks.HuksTag.HUKS_TAG_PADDING,
        value: huks.HuksKeyPadding.HUKS_PADDING_NONE
      },
      {
        tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
        value: huks.HuksCipherMode.HUKS_MODE_GCM
      },
      {
        tag: huks.HuksTag.HUKS_TAG_NONCE,
        value: nonce
      },
      {
        tag: huks.HuksTag.HUKS_TAG_IV,
        value: nonce
      },
      {
        tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
        value: aad
      },
      {
        tag: huks.HuksTag.HUKS_TAG_AE_TAG_LEN,
        value: tagLength
      }
    ];
    if (tag !== undefined) {
      properties.push({
        tag: huks.HuksTag.HUKS_TAG_AE_TAG,
        value: tag
      });
    }
    return {
      properties
    };
  }

  async importSpaceKey(encryptedSpaceKeyRef: string, key: Uint8Array): Promise<SpaceKeyHuksImportResult> {
    const alias = this.huksAliasFromRef(encryptedSpaceKeyRef);
    if (!alias.ok || alias.huksAlias === undefined) {
      return alias;
    }
    if (key.length !== SPACE_KEY_BYTES) {
      return failed(SpaceKeyHuksError.INVALID_KEY, 'spaceKey');
    }

    if (await this.keyExists(alias.huksAlias)) {
      return {
        ok: true,
        encryptedSpaceKeyRef,
        huksAlias: alias.huksAlias
      };
    }

    try {
      await huks.importKeyItem(alias.huksAlias, this.importOptions(key));
      return {
        ok: true,
        encryptedSpaceKeyRef,
        huksAlias: alias.huksAlias
      };
    } catch (_) {
      const existing = await this.keyExists(alias.huksAlias);
      if (existing) {
        return {
          ok: true,
          encryptedSpaceKeyRef,
          huksAlias: alias.huksAlias
        };
      }
      return failed(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, 'importKeyItem');
    }
  }

  async encryptBase64Url(
    encryptedSpaceKeyRef: string,
    nonceBase64Url: string,
    aadBase64Url: string,
    plaintextBase64Url: string
  ): Promise<SpaceKeyHuksEncryptResult> {
    const alias = this.huksAliasFromRef(encryptedSpaceKeyRef);
    if (!alias.ok || alias.huksAlias === undefined) {
      return failedEncrypt(alias.error ?? SpaceKeyHuksError.INVALID_KEY_REF, alias.field ?? 'encryptedSpaceKeyRef');
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

    for (const tagLength of AES_GCM_TAG_LENGTH_CANDIDATES) {
      const encrypted = await this.tryEncrypt(alias.huksAlias, nonce.value, aad.value, plaintext.value, tagLength);
      if (encrypted.ok) {
        return encrypted;
      }
      if (tagLength === AES_GCM_TAG_LENGTH_CANDIDATES[AES_GCM_TAG_LENGTH_CANDIDATES.length - 1]) {
        return encrypted;
      }
    }
    return failedEncrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, 'encryptSession');
  }

  async decryptBase64Url(
    encryptedSpaceKeyRef: string,
    nonceBase64Url: string,
    aadBase64Url: string,
    bodyBase64Url: string,
    tagBase64Url: string
  ): Promise<SpaceKeyHuksDecryptResult> {
    const alias = this.huksAliasFromRef(encryptedSpaceKeyRef);
    if (!alias.ok || alias.huksAlias === undefined) {
      return failedDecrypt(alias.error ?? SpaceKeyHuksError.INVALID_KEY_REF, alias.field ?? 'encryptedSpaceKeyRef');
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

    for (const tagLength of AES_GCM_TAG_LENGTH_CANDIDATES) {
      const decrypted = await this.tryDecrypt(alias.huksAlias, nonce.value, aad.value, body.value, tag.value, tagLength);
      if (decrypted.ok) {
        return decrypted;
      }
      if (tagLength === AES_GCM_TAG_LENGTH_CANDIDATES[AES_GCM_TAG_LENGTH_CANDIDATES.length - 1]) {
        return decrypted;
      }
    }
    return failedDecrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, 'decryptSession');
  }

  private async keyExists(huksAlias: string): Promise<boolean> {
    try {
      if (await huks.hasKeyItem(huksAlias, {})) {
        return true;
      }
    } catch (_) {
    }
    try {
      return await huks.isKeyItemExist(huksAlias, {});
    } catch (_) {
      return false;
    }
  }

  private async tryEncrypt(
    huksAlias: string,
    nonce: Uint8Array,
    aad: Uint8Array,
    plaintext: Uint8Array,
    tagLength: number
  ): Promise<SpaceKeyHuksEncryptResult> {
    const options = this.operationOptions(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT,
      nonce,
      aad,
      undefined,
      tagLength
    );
    let session: huks.HuksSessionHandle;
    try {
      session = await huks.initSession(huksAlias, options);
    } catch (error) {
      return failedEncrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, stageWithCode('initEncrypt', error));
    }

    try {
      const encrypted = await huks.finishSession(session.handle, withInput(options, plaintext));
      const outData = encrypted.outData;
      if (outData === undefined || outData.length < AES_GCM_TAG_BYTES) {
        return failedEncrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, `finishEncrypt:empty:${tagLength}`);
      }
      return {
        ok: true,
        body: encodeBase64Url(outData.subarray(0, outData.length - AES_GCM_TAG_BYTES)),
        tag: encodeBase64Url(outData.subarray(outData.length - AES_GCM_TAG_BYTES))
      };
    } catch (error) {
      return failedEncrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, stageWithCode('finishEncrypt', error, tagLength));
    }
  }

  private async tryDecrypt(
    huksAlias: string,
    nonce: Uint8Array,
    aad: Uint8Array,
    body: Uint8Array,
    tag: Uint8Array,
    tagLength: number
  ): Promise<SpaceKeyHuksDecryptResult> {
    const options = this.operationOptions(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      nonce,
      aad,
      tag,
      tagLength
    );
    let session: huks.HuksSessionHandle;
    try {
      session = await huks.initSession(huksAlias, options);
    } catch (error) {
      return failedDecrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, stageWithCode('initDecrypt', error, tagLength));
    }

    try {
      const decrypted = await huks.finishSession(session.handle, withInput(options, body));
      if (decrypted.outData === undefined) {
        return failedDecrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, `finishDecrypt:empty:${tagLength}`);
      }
      return {
        ok: true,
        plaintext: encodeBase64Url(decrypted.outData)
      };
    } catch (error) {
      return failedDecrypt(SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED, stageWithCode('finishDecrypt', error, tagLength));
    }
  }
}

interface DecodeBytesResult {
  ok: boolean;
  value?: Uint8Array;
  error: SpaceKeyHuksError;
  field: string;
}

function decodeRequired(value: string, expectedBytes: number, field: string): DecodeBytesResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return decodeFailed(SpaceKeyHuksError.INVALID_BASE64URL, field);
  }
  if (decoded.length !== expectedBytes) {
    return decodeFailed(SpaceKeyHuksError.INVALID_LENGTH, field);
  }
  return decodeOk(decoded, field);
}

function decodeOptional(value: string, field: string): DecodeBytesResult {
  const decoded = decodeBase64Url(value);
  if (decoded === null) {
    return decodeFailed(SpaceKeyHuksError.INVALID_BASE64URL, field);
  }
  return decodeOk(decoded, field);
}

function decodeOk(value: Uint8Array, field: string): DecodeBytesResult {
  return {
    ok: true,
    value,
    error: SpaceKeyHuksError.PLATFORM_CRYPTO_FAILED,
    field
  };
}

function decodeFailed(error: SpaceKeyHuksError, field: string): DecodeBytesResult {
  return {
    ok: false,
    error,
    field
  };
}

function withInput(options: huks.HuksOptions, inData: Uint8Array): huks.HuksOptions {
  return {
    properties: options.properties,
    inData
  };
}

function failedEncrypt(error: SpaceKeyHuksError, field: string): SpaceKeyHuksEncryptResult {
  return {
    ok: false,
    error,
    field
  };
}

function failedDecrypt(error: SpaceKeyHuksError, field: string): SpaceKeyHuksDecryptResult {
  return {
    ok: false,
    error,
    field
  };
}

function failed(error: SpaceKeyHuksError, field: string): SpaceKeyHuksImportResult {
  return {
    ok: false,
    encryptedSpaceKeyRef: '',
    error,
    field
  };
}

function stageWithCode(stage: string, error: Object, tagLength?: number): string {
  const code = errorCode(error);
  const suffix = tagLength === undefined ? '' : `:${tagLength}`;
  if (code.length <= 0) {
    return `${stage}${suffix}`;
  }
  return `${stage}:${code}${suffix}`;
}

function errorCode(error: Object): string {
  let serialized = '';
  try {
    serialized = JSON.stringify(error);
  } catch (_) {
    return '';
  }
  const match = /"code"\s*:\s*"?([0-9A-Za-z_-]+)"?/.exec(serialized);
  if (match === null) {
    return '';
  }
  return match[1];
}
