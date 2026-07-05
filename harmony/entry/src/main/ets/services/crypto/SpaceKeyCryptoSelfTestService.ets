import {
  encodeBase64Url
} from './CryptoVectorService';
import {
  SpaceKeyHuksDecryptResult,
  SpaceKeyHuksEncryptResult,
  SpaceKeyHuksService
} from './SpaceKeyHuksService';

const SELF_TEST_AAD: string = 'eggclip:huks-space-key-self-test:v1';
const SELF_TEST_PLAINTEXT: string = 'EggClip HUKS space key self-test v1';

export enum SpaceKeyCryptoSelfTestError {
  NO_SPACE_KEY = 'noSpaceKey',
  ENCRYPT_FAILED = 'encryptFailed',
  DECRYPT_FAILED = 'decryptFailed',
  PLAINTEXT_MISMATCH = 'plaintextMismatch',
  STORE_FAILED = 'storeFailed'
}

export interface SpaceKeyCryptoSelfTestResult {
  ok: boolean;
  error?: SpaceKeyCryptoSelfTestError;
  field?: string;
}

export interface SpaceKeyRefProvider {
  loadLatestEncryptedSpaceKeyRef(): Promise<string | null>;
}

export interface SpaceKeyAesGcmGateway {
  encryptBase64Url(
    encryptedSpaceKeyRef: string,
    nonceBase64Url: string,
    aadBase64Url: string,
    plaintextBase64Url: string
  ): Promise<SpaceKeyHuksEncryptResult>;

  decryptBase64Url(
    encryptedSpaceKeyRef: string,
    nonceBase64Url: string,
    aadBase64Url: string,
    bodyBase64Url: string,
    tagBase64Url: string
  ): Promise<SpaceKeyHuksDecryptResult>;
}

export class SpaceKeyCryptoSelfTestService {
  private readonly keyRefProvider: SpaceKeyRefProvider;
  private readonly crypto: SpaceKeyAesGcmGateway;

  constructor(
    keyRefProvider: SpaceKeyRefProvider,
    crypto: SpaceKeyAesGcmGateway = new SpaceKeyHuksService()
  ) {
    this.keyRefProvider = keyRefProvider;
    this.crypto = crypto;
  }

  async run(): Promise<SpaceKeyCryptoSelfTestResult> {
    let encryptedSpaceKeyRef: string | null = null;
    try {
      encryptedSpaceKeyRef = await this.keyRefProvider.loadLatestEncryptedSpaceKeyRef();
    } catch (_) {
      return failed(SpaceKeyCryptoSelfTestError.STORE_FAILED, 'loadLatestEncryptedSpaceKeyRef');
    }
    if (encryptedSpaceKeyRef === null || encryptedSpaceKeyRef.length <= 0) {
      return failed(SpaceKeyCryptoSelfTestError.NO_SPACE_KEY, 'encryptedSpaceKeyRef');
    }

    const nonce = encodeBase64Url(new Uint8Array([0x45, 0x67, 0x67, 0x43, 0x6c, 0x69, 0x70, 0x2d, 0x54, 0x31, 0x30, 0x31]));
    const aad = encodeBase64Url(utf8Encode(SELF_TEST_AAD));
    const plaintext = encodeBase64Url(utf8Encode(SELF_TEST_PLAINTEXT));

    const encrypted = await this.crypto.encryptBase64Url(encryptedSpaceKeyRef, nonce, aad, plaintext);
    if (!encrypted.ok || encrypted.body === undefined || encrypted.tag === undefined) {
      return failed(SpaceKeyCryptoSelfTestError.ENCRYPT_FAILED, encrypted.field ?? 'encryptBase64Url');
    }

    const decrypted = await this.crypto.decryptBase64Url(encryptedSpaceKeyRef, nonce, aad, encrypted.body, encrypted.tag);
    if (!decrypted.ok || decrypted.plaintext === undefined) {
      return failed(SpaceKeyCryptoSelfTestError.DECRYPT_FAILED, decrypted.field ?? 'decryptBase64Url');
    }
    if (decrypted.plaintext !== plaintext) {
      return failed(SpaceKeyCryptoSelfTestError.PLAINTEXT_MISMATCH, 'plaintext');
    }

    return {
      ok: true
    };
  }
}

function failed(error: SpaceKeyCryptoSelfTestError, field: string): SpaceKeyCryptoSelfTestResult {
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
    } else {
      bytes.push(0xe0 | (code >> 12));
      bytes.push(0x80 | ((code >> 6) & 0x3f));
      bytes.push(0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(bytes);
}
