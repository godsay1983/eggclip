import { JsonObject } from '../../models/ProtocolModels';
import { decodeBase64Url } from '../crypto/CryptoVectorService';
import {
  SpaceKeyHuksService,
  SpaceKeySecureImporter
} from '../crypto/SpaceKeyHuksService';
import { SpaceKeyReferenceService } from '../crypto/SpaceKeyReferenceService';

export const INITIAL_SPACE_KEY_DELIVERY: string = 'pairing-v1';
export const ROTATED_SPACE_KEY_DELIVERY: string = 'rotation-v1';

export enum SpaceKeyDeliveryError {
  MISSING_PAYLOAD = 'missingPayload',
  INVALID_SPACE_ID = 'invalidSpaceId',
  INVALID_KEY_VERSION = 'invalidKeyVersion',
  INVALID_DELIVERY = 'invalidDelivery',
  INVALID_SPACE_KEY = 'invalidSpaceKey',
  INVALID_ALIAS = 'invalidAlias',
  IMPORT_FAILED = 'importFailed'
}

export interface SpaceKeyDeliveryInput {
  payload?: JsonObject;
  expectedSpaceId: string;
  expectedKeyVersion: number;
}

export interface SpaceKeyRotationInput {
  payload?: JsonObject;
  expectedSpaceId: string;
  currentKeyVersion: number;
}

export interface SpaceKeyDeliveryResult {
  ok: boolean;
  encryptedSpaceKeyRef: string;
  error?: SpaceKeyDeliveryError;
  field?: string;
}

export class SpaceKeyDeliveryService {
  private readonly referenceService: SpaceKeyReferenceService;
  private readonly secureImporter: SpaceKeySecureImporter;

  constructor(
    referenceService: SpaceKeyReferenceService = new SpaceKeyReferenceService(),
    secureImporter: SpaceKeySecureImporter = new SpaceKeyHuksService()
  ) {
    this.referenceService = referenceService;
    this.secureImporter = secureImporter;
  }

  async acceptInitialDelivery(input: SpaceKeyDeliveryInput): Promise<SpaceKeyDeliveryResult> {
    return this.acceptDelivery(
      input.payload,
      input.expectedSpaceId,
      input.expectedKeyVersion,
      INITIAL_SPACE_KEY_DELIVERY,
      false
    );
  }

  async acceptRotation(input: SpaceKeyRotationInput): Promise<SpaceKeyDeliveryResult> {
    return this.acceptDelivery(
      input.payload,
      input.expectedSpaceId,
      input.currentKeyVersion,
      ROTATED_SPACE_KEY_DELIVERY,
      true
    );
  }

  private async acceptDelivery(
    payload: JsonObject | undefined,
    expectedSpaceId: string,
    expectedKeyVersion: number,
    expectedDelivery: string,
    requireNewerVersion: boolean
  ): Promise<SpaceKeyDeliveryResult> {
    if (payload === undefined) {
      return failed(SpaceKeyDeliveryError.MISSING_PAYLOAD, 'payload');
    }

    const spaceId = readString(payload, 'spaceId');
    if (spaceId !== expectedSpaceId) {
      return failed(SpaceKeyDeliveryError.INVALID_SPACE_ID, 'spaceId');
    }

    const keyVersion = readNumber(payload, 'keyVersion');
    const validVersion = requireNewerVersion ? keyVersion > expectedKeyVersion : keyVersion === expectedKeyVersion;
    if (!Number.isSafeInteger(keyVersion) || !validVersion) {
      return failed(SpaceKeyDeliveryError.INVALID_KEY_VERSION, 'keyVersion');
    }

    const delivery = readString(payload, 'delivery');
    if (delivery !== expectedDelivery) {
      return failed(SpaceKeyDeliveryError.INVALID_DELIVERY, 'delivery');
    }

    const decoded = decodeBase64Url(readString(payload, 'spaceKey'));
    if (decoded === null) {
      return failed(SpaceKeyDeliveryError.INVALID_SPACE_KEY, 'spaceKey');
    }

    try {
      const inspected = this.referenceService.inspectImportedSpaceKey(decoded);
      if (!inspected.ok) {
        return failed(SpaceKeyDeliveryError.INVALID_SPACE_KEY, 'spaceKey');
      }

      const alias = this.referenceService.buildHuksAlias(spaceId, keyVersion);
      if (!alias.ok || alias.alias.length <= 0) {
        return failed(SpaceKeyDeliveryError.INVALID_ALIAS, 'encryptedSpaceKeyRef');
      }

      const imported = await this.secureImporter.importSpaceKey(alias.alias, decoded);
      if (!imported.ok) {
        return failed(SpaceKeyDeliveryError.IMPORT_FAILED, imported.field ?? 'importKeyItem');
      }

      return {
        ok: true,
        encryptedSpaceKeyRef: alias.alias
      };
    } finally {
      decoded.fill(0);
    }
  }
}

function readString(payload: JsonObject, field: string): string {
  const value = payload[field];
  return typeof value === 'string' ? value : '';
}

function readNumber(payload: JsonObject, field: string): number {
  const value = payload[field];
  return typeof value === 'number' ? value : Number.NaN;
}

function failed(error: SpaceKeyDeliveryError, field: string): SpaceKeyDeliveryResult {
  return {
    ok: false,
    encryptedSpaceKeyRef: '',
    error,
    field
  };
}
