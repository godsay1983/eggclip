import {
  Ed25519HuksIdentityError,
  Ed25519HuksIdentityMaterialResult,
  Ed25519HuksIdentityService,
  Ed25519HuksKeyRefResult
} from './Ed25519HuksIdentityService';

export enum LocalDeviceIdentityError {
  STORAGE_FAILED = 'storageFailed',
  HUKS_FAILED = 'huksFailed',
  INVALID_HUKS_REF = 'invalidHuksRef'
}

export interface LocalDeviceIdentity {
  deviceId: string;
  identityPublicKey: string;
  identityPrivateKeyRef: string;
}

export interface LocalDeviceIdentityResult {
  ok: boolean;
  identity?: LocalDeviceIdentity;
  created?: boolean;
  error?: LocalDeviceIdentityError;
  huksError?: Ed25519HuksIdentityError;
  field?: string;
}

export interface LocalDeviceIdentityMetadataGateway {
  getOrCreateDeviceId(updatedAt: number): Promise<string>;
  loadLocalIdentityPublicKey(): Promise<string | null>;
  saveLocalIdentityPublicKey(identityPublicKey: string, updatedAt: number): Promise<void>;
  loadLocalIdentityPrivateKeyRef(): Promise<string | null>;
  saveLocalIdentityPrivateKeyRef(identityPrivateKeyRef: string, updatedAt: number): Promise<void>;
}

export interface LocalDeviceSecureIdentityGateway {
  buildLocalIdentityPrivateKeyRef(aliasSlot?: string): Ed25519HuksKeyRefResult;
  generateOrLoadIdentity(identityPrivateKeyRef: string): Promise<Ed25519HuksIdentityMaterialResult>;
}

export class LocalDeviceIdentityService {
  private readonly metadata: LocalDeviceIdentityMetadataGateway;
  private readonly secureIdentity: LocalDeviceSecureIdentityGateway;

  constructor(
    metadata: LocalDeviceIdentityMetadataGateway,
    secureIdentity: LocalDeviceSecureIdentityGateway = new Ed25519HuksIdentityService()
  ) {
    this.metadata = metadata;
    this.secureIdentity = secureIdentity;
  }

  async ensureLocalIdentity(
    nowMs: number = Date.now(),
    aliasSlot: string = 'v1'
  ): Promise<LocalDeviceIdentityResult> {
    try {
      const deviceId = await this.metadata.getOrCreateDeviceId(nowMs);
      const existingPublicKey = await this.metadata.loadLocalIdentityPublicKey();
      const existingPrivateKeyRef = await this.metadata.loadLocalIdentityPrivateKeyRef();

      if (existingPublicKey !== null && existingPrivateKeyRef !== null) {
        return {
          ok: true,
          created: false,
          identity: {
            deviceId,
            identityPublicKey: existingPublicKey,
            identityPrivateKeyRef: existingPrivateKeyRef
          }
        };
      }

      const privateKeyRef = existingPrivateKeyRef ?? this.buildNewPrivateKeyRef(aliasSlot);
      if (privateKeyRef === null) {
        return failed(LocalDeviceIdentityError.INVALID_HUKS_REF, 'identityPrivateKeyRef');
      }

      const generated = await this.secureIdentity.generateOrLoadIdentity(privateKeyRef);
      if (!generated.ok || generated.identityPublicKey === undefined ||
        generated.identityPrivateKeyRef === undefined) {
        return failed(
          LocalDeviceIdentityError.HUKS_FAILED,
          generated.field ?? 'identity',
          generated.error
        );
      }

      await this.metadata.saveLocalIdentityPublicKey(generated.identityPublicKey, nowMs);
      await this.metadata.saveLocalIdentityPrivateKeyRef(generated.identityPrivateKeyRef, nowMs);

      return {
        ok: true,
        created: true,
        identity: {
          deviceId,
          identityPublicKey: generated.identityPublicKey,
          identityPrivateKeyRef: generated.identityPrivateKeyRef
        }
      };
    } catch (_) {
      return failed(LocalDeviceIdentityError.STORAGE_FAILED, 'metadata');
    }
  }

  private buildNewPrivateKeyRef(aliasSlot: string): string | null {
    const refResult = this.secureIdentity.buildLocalIdentityPrivateKeyRef(aliasSlot);
    if (!refResult.ok || refResult.identityPrivateKeyRef === undefined) {
      return null;
    }
    return refResult.identityPrivateKeyRef;
  }
}

function failed(
  error: LocalDeviceIdentityError,
  field: string,
  huksError?: Ed25519HuksIdentityError
): LocalDeviceIdentityResult {
  return {
    ok: false,
    error,
    huksError,
    field
  };
}
