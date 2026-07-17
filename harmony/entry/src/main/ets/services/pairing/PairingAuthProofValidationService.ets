import {
  AuthProofPayload,
  AuthRole
} from '../../models/ProtocolModels';
import {
  CryptoVectorErrorCode,
  CryptoVectorService,
  decodeBase64Url
} from '../crypto/CryptoVectorService';
import {
  sha256Utf8Base64Url
} from '../crypto/Sha256Service';
import {
  PairingAuthTranscriptDraft
} from './PairingHandshakeDraftService';

export enum PairingAuthProofValidationError {
  ROLE_MISMATCH = 'roleMismatch',
  TRANSCRIPT_HASH_MISMATCH = 'transcriptHashMismatch',
  INVALID_SIGNATURE = 'invalidSignature',
  INVALID_TRANSCRIPT = 'invalidTranscript',
  SIGNATURE_VERIFY_FAILED = 'signatureVerifyFailed'
}

export interface PairingAuthProofValidationResult {
  ok: boolean;
  error?: PairingAuthProofValidationError;
  cryptoError?: CryptoVectorErrorCode;
  field?: string;
}

export interface PairingAuthProofValidator {
  verifyPayloadSignatureAgainstTranscript(
    payload: AuthProofPayload,
    expectedRole: AuthRole,
    transcript: PairingAuthTranscriptDraft,
    remoteIdentityPublicKey: string
  ): PairingAuthProofValidationResult;
}

export class PairingAuthProofValidationService implements PairingAuthProofValidator {
  private readonly crypto: CryptoVectorService = new CryptoVectorService();

  validatePayloadAgainstTranscript(
    payload: AuthProofPayload,
    expectedRole: AuthRole,
    transcript: PairingAuthTranscriptDraft
  ): PairingAuthProofValidationResult {
    if (payload.role !== expectedRole) {
      return failed(PairingAuthProofValidationError.ROLE_MISMATCH, 'role');
    }
    if (transcript.canonicalTranscript.length === 0 || transcript.input.role !== expectedRole) {
      return failed(PairingAuthProofValidationError.INVALID_TRANSCRIPT, 'canonicalTranscript');
    }
    const expectedHash = sha256Utf8Base64Url(transcript.canonicalTranscript);
    if (payload.transcriptHash !== expectedHash) {
      return failed(PairingAuthProofValidationError.TRANSCRIPT_HASH_MISMATCH, 'transcriptHash');
    }
    const signature = decodeBase64Url(payload.signature);
    if (signature === null || signature.length !== 64) {
      return failed(PairingAuthProofValidationError.INVALID_SIGNATURE, 'signature');
    }
    return { ok: true };
  }

  verifyPayloadSignatureAgainstTranscript(
    payload: AuthProofPayload,
    expectedRole: AuthRole,
    transcript: PairingAuthTranscriptDraft,
    remoteIdentityPublicKey: string
  ): PairingAuthProofValidationResult {
    const shape = this.validatePayloadAgainstTranscript(payload, expectedRole, transcript);
    if (!shape.ok) {
      return shape;
    }

    const verified = this.crypto.verifyEd25519Signature(
      remoteIdentityPublicKey,
      transcript.canonicalTranscript,
      payload.signature
    );
    if (!verified.ok) {
      return {
        ok: false,
        error: PairingAuthProofValidationError.SIGNATURE_VERIFY_FAILED,
        cryptoError: verified.error,
        field: verified.field
      };
    }
    return { ok: true };
  }
}

function failed(
  error: PairingAuthProofValidationError,
  field: string
): PairingAuthProofValidationResult {
  return {
    ok: false,
    error,
    field
  };
}
