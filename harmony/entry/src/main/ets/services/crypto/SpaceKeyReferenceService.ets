export const INITIAL_SPACE_KEY_VERSION: number = 1;
export const SPACE_KEY_BYTES: number = 32;

export enum SpaceKeyReferenceError {
  INVALID_SPACE_ID = 'invalidSpaceId',
  INVALID_KEY_VERSION = 'invalidKeyVersion',
  INVALID_KEY_LENGTH = 'invalidKeyLength'
}

export interface SpaceKeyReferenceResult {
  ok: boolean;
  alias: string;
  error?: SpaceKeyReferenceError;
}

export class SpaceKeyReferenceService {
  buildHuksAlias(spaceId: string, keyVersion: number): SpaceKeyReferenceResult {
    if (!isUuid(spaceId)) {
      return {
        ok: false,
        alias: '',
        error: SpaceKeyReferenceError.INVALID_SPACE_ID
      };
    }
    if (!Number.isSafeInteger(keyVersion) || keyVersion <= 0 || keyVersion > 0xffff) {
      return {
        ok: false,
        alias: '',
        error: SpaceKeyReferenceError.INVALID_KEY_VERSION
      };
    }
    return {
      ok: true,
      alias: `huks://eggclip/space-key/${spaceId}/v${keyVersion}`
    };
  }

  inspectImportedSpaceKey(key: Uint8Array): SpaceKeyReferenceResult {
    if (key.length !== SPACE_KEY_BYTES) {
      return {
        ok: false,
        alias: '',
        error: SpaceKeyReferenceError.INVALID_KEY_LENGTH
      };
    }
    return {
      ok: true,
      alias: ''
    };
  }
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
