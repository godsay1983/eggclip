import { decodeBase64Url } from '../crypto/CryptoVectorService';
import {
  AuthRole,
  AuthTranscriptInput,
  Capability,
  HelloPayload,
  canonicalAuthTranscript
} from '../../models/ProtocolModels';
import { PairingInvitationPayload } from './PairingInvitationService';

const IDENTITY_PUBLIC_KEY_BYTES: number = 32;
const EPHEMERAL_PUBLIC_KEY_BYTES: number = 32;

export enum PairingHandshakeDraftError {
  MISSING_PENDING_INVITATION = 'missingPendingInvitation',
  MISSING_INVITATION_ID = 'missingInvitationId',
  EXPIRED_INVITATION = 'expiredInvitation',
  SERVER_HELLO_MISMATCH = 'serverHelloMismatch',
  INVALID_FIELD = 'invalidField'
}

export interface PairingHandshakeDraft {
  invitationId: string;
  spaceId: string;
  spaceKeyVersion: number;
  remoteDeviceId: string;
  remoteIdentityPublicKey: string;
  pairingContext: string;
  clientHelloPayload: HelloPayload;
  expiresAtMs: number;
}

export interface PairingHandshakeDraftResult {
  ok: boolean;
  draft?: PairingHandshakeDraft;
  error?: PairingHandshakeDraftError;
  field?: string;
}

export interface PairingAuthTranscriptDraft {
  input: AuthTranscriptInput;
  canonicalTranscript: string;
}

export interface PairingAuthTranscriptDraftResult {
  ok: boolean;
  transcript?: PairingAuthTranscriptDraft;
  error?: PairingHandshakeDraftError;
  field?: string;
}

export interface PairingHandshakeDraftInput {
  invitation: PairingInvitationPayload | null;
  localDeviceId: string;
  localIdentityPublicKey: string;
  localEphemeralPublicKey: string;
  nowMs: number;
}

export class PairingHandshakeDraftService {
  buildClientHandshakeDraft(input: PairingHandshakeDraftInput): PairingHandshakeDraftResult {
    if (input.invitation === null) {
      return { ok: false, error: PairingHandshakeDraftError.MISSING_PENDING_INVITATION };
    }
    if (input.invitation.invitationId === undefined || !isUuid(input.invitation.invitationId)) {
      return { ok: false, error: PairingHandshakeDraftError.MISSING_INVITATION_ID, field: 'invitationId' };
    }
    if (input.invitation.expiresAtMs <= input.nowMs) {
      return { ok: false, error: PairingHandshakeDraftError.EXPIRED_INVITATION, field: 'expiresAtMs' };
    }
    if (!isUuid(input.invitation.spaceId)) {
      return invalidField('spaceId');
    }
    if (!Number.isSafeInteger(input.invitation.spaceKeyVersion) || input.invitation.spaceKeyVersion <= 0) {
      return invalidField('spaceKeyVersion');
    }
    if (!isUuid(input.invitation.issuerDeviceId)) {
      return invalidField('issuerDeviceId');
    }
    if (!hasBase64UrlLength(input.invitation.issuerIdentityPublicKey, IDENTITY_PUBLIC_KEY_BYTES)) {
      return invalidField('issuerIdentityPublicKey');
    }
    if (!isUuid(input.localDeviceId)) {
      return invalidField('localDeviceId');
    }
    if (!hasBase64UrlLength(input.localIdentityPublicKey, IDENTITY_PUBLIC_KEY_BYTES)) {
      return invalidField('localIdentityPublicKey');
    }
    if (!hasBase64UrlLength(input.localEphemeralPublicKey, EPHEMERAL_PUBLIC_KEY_BYTES)) {
      return invalidField('localEphemeralPublicKey');
    }

    const clientHelloPayload: HelloPayload = {
      spaceId: input.invitation.spaceId,
      deviceId: input.localDeviceId,
      identityPublicKey: input.localIdentityPublicKey,
      ephemeralPublicKey: input.localEphemeralPublicKey,
      capabilities: [
        Capability.TEXT_PLAIN,
        Capability.SYNC_HEADS,
        Capability.ITEM_BATCH,
        Capability.ITEM_LIVE
      ]
    };

    return {
      ok: true,
      draft: {
        invitationId: input.invitation.invitationId,
        spaceId: input.invitation.spaceId,
        spaceKeyVersion: input.invitation.spaceKeyVersion,
        remoteDeviceId: input.invitation.issuerDeviceId,
        remoteIdentityPublicKey: input.invitation.issuerIdentityPublicKey,
        pairingContext: `pairing-invitation:v1:${input.invitation.invitationId}`,
        clientHelloPayload,
        expiresAtMs: input.invitation.expiresAtMs
      }
    };
  }

  buildClientAuthTranscriptDraft(
    draft: PairingHandshakeDraft,
    serverHelloPayload: HelloPayload
  ): PairingAuthTranscriptDraftResult {
    if (serverHelloPayload.spaceId !== draft.spaceId) {
      return mismatch('spaceId');
    }
    if (serverHelloPayload.deviceId !== draft.remoteDeviceId) {
      return mismatch('deviceId');
    }
    if (serverHelloPayload.identityPublicKey !== draft.remoteIdentityPublicKey) {
      return mismatch('identityPublicKey');
    }
    if (!hasBase64UrlLength(serverHelloPayload.ephemeralPublicKey, EPHEMERAL_PUBLIC_KEY_BYTES)) {
      return invalidTranscriptField('ephemeralPublicKey');
    }
    if (serverHelloPayload.capabilities.indexOf(Capability.TEXT_PLAIN) < 0) {
      return invalidTranscriptField('capabilities');
    }

    const input: AuthTranscriptInput = {
      role: AuthRole.CLIENT,
      spaceId: draft.spaceId,
      localDeviceId: draft.clientHelloPayload.deviceId,
      remoteDeviceId: draft.remoteDeviceId,
      localIdentityPublicKey: draft.clientHelloPayload.identityPublicKey,
      remoteIdentityPublicKey: draft.remoteIdentityPublicKey,
      localEphemeralPublicKey: draft.clientHelloPayload.ephemeralPublicKey,
      remoteEphemeralPublicKey: serverHelloPayload.ephemeralPublicKey,
      pairingContext: draft.pairingContext
    };
    const canonicalTranscript = canonicalAuthTranscript(input);
    if (canonicalTranscript === null) {
      return invalidTranscriptField('transcript');
    }
    return {
      ok: true,
      transcript: {
        input,
        canonicalTranscript
      }
    };
  }
}

function invalidField(field: string): PairingHandshakeDraftResult {
  return { ok: false, error: PairingHandshakeDraftError.INVALID_FIELD, field };
}

function invalidTranscriptField(field: string): PairingAuthTranscriptDraftResult {
  return { ok: false, error: PairingHandshakeDraftError.INVALID_FIELD, field };
}

function mismatch(field: string): PairingAuthTranscriptDraftResult {
  return { ok: false, error: PairingHandshakeDraftError.SERVER_HELLO_MISMATCH, field };
}

function hasBase64UrlLength(value: string, expectedBytes: number): boolean {
  const decoded = decodeBase64Url(value);
  return decoded !== null && decoded.length === expectedBytes;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
