import {
  SpaceKeyHuksError,
  SpaceKeyHuksDeleteResult,
  SpaceKeyHuksService
} from './SpaceKeyHuksService';

export enum SpaceKeyRecoveryError {
  STORE_READ_FAILED = 'storeReadFailed',
  HUKS_DELETE_FAILED = 'huksDeleteFailed',
  STORE_RESET_FAILED = 'storeResetFailed'
}

export interface SpaceKeyRecoveryResult {
  ok: boolean;
  clearedKeyRefs: number;
  invalidKeyRefs: number;
  error?: SpaceKeyRecoveryError;
  field?: string;
}

export interface SpaceKeyRecoveryRepository {
  listEncryptedSpaceKeyRefs(): Promise<string[]>;
  resetPairingSecurityState(): Promise<void>;
}

export interface SpaceKeyDestroyer {
  deleteSpaceKey(encryptedSpaceKeyRef: string): Promise<SpaceKeyHuksDeleteResult>;
}

export class SpaceKeyRecoveryService {
  private readonly repository: SpaceKeyRecoveryRepository;
  private readonly huks: SpaceKeyDestroyer;

  constructor(
    repository: SpaceKeyRecoveryRepository,
    huks: SpaceKeyDestroyer = new SpaceKeyHuksService()
  ) {
    this.repository = repository;
    this.huks = huks;
  }

  async reinitializePairingSecurityState(): Promise<SpaceKeyRecoveryResult> {
    let refs: string[] = [];
    try {
      refs = await this.repository.listEncryptedSpaceKeyRefs();
    } catch (_) {
      return failed(SpaceKeyRecoveryError.STORE_READ_FAILED, 'listEncryptedSpaceKeyRefs', 0);
    }
    let cleared = 0;
    let invalid = 0;
    for (const ref of refs) {
      const deleted = await this.huks.deleteSpaceKey(ref);
      if (!deleted.ok) {
        if (deleted.error === SpaceKeyHuksError.INVALID_KEY_REF) {
          invalid += 1;
          continue;
        }
        return failed(SpaceKeyRecoveryError.HUKS_DELETE_FAILED, deleted.field ?? 'deleteSpaceKey', cleared, invalid);
      }
      cleared += 1;
    }
    try {
      await this.repository.resetPairingSecurityState();
    } catch (_) {
      return failed(SpaceKeyRecoveryError.STORE_RESET_FAILED, 'resetPairingSecurityState', cleared, invalid);
    }
    return { ok: true, clearedKeyRefs: cleared, invalidKeyRefs: invalid };
  }
}

function failed(
  error: SpaceKeyRecoveryError,
  field: string,
  clearedKeyRefs: number,
  invalidKeyRefs: number = 0
): SpaceKeyRecoveryResult {
  return { ok: false, clearedKeyRefs, invalidKeyRefs, error, field };
}
