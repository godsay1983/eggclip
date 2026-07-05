import { JsonObject } from '../../models/ProtocolModels';
import { decodeBase64Url } from '../crypto/CryptoVectorService';
import { SpaceKeyReferenceService } from '../crypto/SpaceKeyReferenceService';

export const INITIAL_SPACE_KEY_DELIVERY: string = 'pairing-v1';

export enum SpaceKeyDeliveryError {
  MISSING_PAYLOAD = 'missingPayload',
  INVALID_SPACE_ID = 'invalidSpaceId',
  INVALID_KEY_VERSION = 'invalidKeyVersion',
  INVALID_DELIVERY = 'invalidDelivery',
  INVALID_SPACE_KEY = 'invalidSpaceKey',
  INVALID_ALIAS = 'invalidAlias'
}

export interface SpaceKeyDeliveryInput {
  payload?: JsonObject;
  expectedSpaceId: string;
  expectedKeyVersion: number;
}

export interface SpaceKeyDeliveryResult {
  ok: boolean;
  encryptedSpaceKeyRef: string;
  error?: SpaceKeyDeliveryError;
  field?: string;
}

export class SpaceKeyDeliveryService {
  private readonly referenceService: SpaceKeyReferenceService;

  constructor(referenceService: SpaceKeyReferenceService = new SpaceKeyReferenceService()) {
    this.referenceService = referenceService;
  }

  acceptInitialDelivery(input: SpaceKeyDeliveryInput): SpaceKeyDeliveryResult {
    if (input.payload === undefined) {
      return failed(SpaceKeyDeliveryError.MISSING_PAYLOAD, 'payload');
    }

    const spaceId = readString(input.payload, 'spaceId');
    if (spaceId !== input.expectedSpaceId) {
      return failed(SpaceKeyDeliveryError.INVALID_SPACE_ID, 'spaceId');
    }

    const keyVersion = readNumber(input.payload, 'keyVersion');
    if (!Number.isSafeInteger(keyVersion) || keyVersion !== input.expectedKeyVersion) {
      return failed(SpaceKeyDeliveryError.INVALID_KEY_VERSION, 'keyVersion');
    }

    const delivery = readString(input.payload, 'delivery');
    if (delivery !== INITIAL_SPACE_KEY_DELIVERY) {
      return failed(SpaceKeyDeliveryError.INVALID_DELIVERY, 'delivery');
    }

    const decoded = decodeBase64Url(readString(input.payload, 'spaceKey'));
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
