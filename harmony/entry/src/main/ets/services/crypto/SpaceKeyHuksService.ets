import huks from '@ohos.security.huks';
import { SPACE_KEY_BYTES } from './SpaceKeyReferenceService';

const SPACE_KEY_REF_PREFIX: string = 'huks://eggclip/space-key/';
const SPACE_KEY_ALIAS_PREFIX: string = 'eggclip.space-key.';

export enum SpaceKeyHuksError {
  INVALID_KEY_REF = 'invalidKeyRef',
  INVALID_KEY = 'invalidKey',
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

  async importSpaceKey(encryptedSpaceKeyRef: string, key: Uint8Array): Promise<SpaceKeyHuksImportResult> {
    const alias = this.huksAliasFromRef(encryptedSpaceKeyRef);
    if (!alias.ok || alias.huksAlias === undefined) {
      return alias;
    }
    if (key.length !== SPACE_KEY_BYTES) {
      return failed(SpaceKeyHuksError.INVALID_KEY, 'spaceKey');
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

  private async keyExists(huksAlias: string): Promise<boolean> {
    try {
      return await huks.isKeyItemExist(huksAlias, {});
    } catch (_) {
      return false;
    }
  }
}

function failed(error: SpaceKeyHuksError, field: string): SpaceKeyHuksImportResult {
  return {
    ok: false,
    encryptedSpaceKeyRef: '',
    error,
    field
  };
}
