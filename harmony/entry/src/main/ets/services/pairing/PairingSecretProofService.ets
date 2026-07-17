import { HelloPayload } from '../../models/ProtocolModels';
import { decodeBase64Url, encodeBase64Url } from '../crypto/CryptoVectorService';
import { sha256, utf8Encode } from '../crypto/Sha256Service';
import { PairingInvitationPayload } from './PairingInvitationService';

export enum PairingSecretProofError {
  INVALID_INVITATION = 'invalidInvitation',
  INVALID_CLIENT_HELLO = 'invalidClientHello'
}

export interface PairingSecretProofResult {
  ok: boolean;
  proof?: string;
  verifier?: string;
  claim?: string;
  error?: PairingSecretProofError;
}

export class PairingSecretProofService {
  build(invitation: PairingInvitationPayload, clientHello: HelloPayload): PairingSecretProofResult {
    if (invitation.version !== 2 || invitation.invitationId === undefined) {
      return { ok: false, error: PairingSecretProofError.INVALID_INVITATION };
    }
    const pairingSecret = decodeBase64Url(invitation.pairingSecret);
    if (pairingSecret === null || pairingSecret.length !== 32) {
      return { ok: false, error: PairingSecretProofError.INVALID_INVITATION };
    }
    if (clientHello.spaceId !== invitation.spaceId ||
      clientHello.pairingContext !== `pairing-invitation:v2:${invitation.invitationId}`) {
      return { ok: false, error: PairingSecretProofError.INVALID_CLIENT_HELLO };
    }

    const verifierInput = `EggClip pairing invitation verifier v2\n` +
      `invitationId=${invitation.invitationId}\n` +
      `pairingSecret=${invitation.pairingSecret}\n`;
    const verifierBytes = sha256(utf8Encode(verifierInput));
    const claim = `EggClip pairing secret proof v2\n` +
      `invitationId=${invitation.invitationId}\n` +
      `spaceId=${invitation.spaceId}\n` +
      `issuerDeviceId=${invitation.issuerDeviceId}\n` +
      `issuerIdentityPublicKey=${invitation.issuerIdentityPublicKey}\n` +
      `clientDeviceId=${clientHello.deviceId}\n` +
      `clientIdentityPublicKey=${clientHello.identityPublicKey}\n` +
      `clientEphemeralPublicKey=${clientHello.ephemeralPublicKey}\n`;
    return {
      ok: true,
      proof: encodeBase64Url(hmacSha256(verifierBytes, utf8Encode(claim))),
      verifier: encodeBase64Url(verifierBytes),
      claim
    };
  }
}

function hmacSha256(key: Uint8Array, message: Uint8Array): Uint8Array {
  const blockSize = 64;
  const normalizedKey = key.length > blockSize ? sha256(key) : key;
  const innerPad = new Uint8Array(blockSize);
  const outerPad = new Uint8Array(blockSize);
  for (let index = 0; index < blockSize; index += 1) {
    const value = index < normalizedKey.length ? normalizedKey[index] : 0;
    innerPad[index] = value ^ 0x36;
    outerPad[index] = value ^ 0x5c;
  }
  const innerInput = new Uint8Array(innerPad.length + message.length);
  innerInput.set(innerPad);
  innerInput.set(message, innerPad.length);
  const innerDigest = sha256(innerInput);
  const outerInput = new Uint8Array(outerPad.length + innerDigest.length);
  outerInput.set(outerPad);
  outerInput.set(innerDigest, outerPad.length);
  return sha256(outerInput);
}
