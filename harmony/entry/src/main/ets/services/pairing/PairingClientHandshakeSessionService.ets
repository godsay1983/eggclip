import {
  AuthRole,
  HelloPayload,
  MessageType,
  ProtocolParser,
  ProtocolSessionState
} from '../../models/ProtocolModels';
import {
  ProtocolFrameBuildError,
  ProtocolFrameBuilderService
} from '../transport/ProtocolFrameBuilderService';
import {
  ProtocolHandshakeFrameOutcome,
  ProtocolHandshakeTransportSession,
  ProtocolSessionKeys,
  ProtocolTransportFrameError
} from '../transport/ProtocolTransportSession';
import {
  ProtocolTransportSession
} from '../transport/ProtocolTransportSession';
import {
  Ed25519SignatureError,
  Ed25519SignatureService
} from '../crypto/Ed25519SignatureService';
import {
  Ed25519HuksIdentityError,
  Ed25519HuksIdentityService,
  Ed25519HuksSignatureResult
} from '../crypto/Ed25519HuksIdentityService';
import {
  SessionKeyDerivationError,
  SessionKeyDerivationService
} from '../crypto/SessionKeyDerivationService';
import { sha256Utf8Base64Url } from '../crypto/Sha256Service';
import {
  X25519KeyAgreementError,
  X25519KeyAgreementService
} from '../crypto/X25519KeyAgreementService';
import {
  PairingAuthTranscriptDraft,
  PairingHandshakeDraft,
  PairingHandshakeDraftError,
  PairingHandshakeDraftService
} from './PairingHandshakeDraftService';
import {
  PairingAuthProofValidationError,
  PairingAuthProofValidator,
  PairingAuthProofValidationService
} from './PairingAuthProofValidationService';

export enum PairingClientHandshakeError {
  CLIENT_HELLO_BUILD_FAILED = 'clientHelloBuildFailed',
  SERVER_FRAME_REJECTED = 'serverFrameRejected',
  UNEXPECTED_SERVER_MESSAGE = 'unexpectedServerMessage',
  INVALID_SERVER_HELLO = 'invalidServerHello',
  SERVER_HELLO_MISMATCH = 'serverHelloMismatch',
  AUTH_PROOF_SIGN_FAILED = 'authProofSignFailed',
  AUTH_PROOF_BUILD_FAILED = 'authProofBuildFailed',
  AUTH_PROOF_NOT_SENT = 'authProofNotSent',
  SERVER_AUTH_PROOF_REJECTED = 'serverAuthProofRejected',
  SERVER_AUTH_PROOF_INVALID = 'serverAuthProofInvalid',
  SERVER_AUTH_PROOF_REQUIRED = 'serverAuthProofRequired',
  AUTH_OK_REJECTED = 'authOkRejected',
  SHARED_SECRET_DERIVATION_FAILED = 'sharedSecretDerivationFailed',
  SESSION_KEY_DERIVATION_FAILED = 'sessionKeyDerivationFailed'
}

export interface PairingClientHandshakeStartResult {
  ok: boolean;
  session?: PairingClientHandshakeSession;
  clientHelloFrame?: string;
  error?: PairingClientHandshakeError;
  frameError?: ProtocolFrameBuildError;
  field?: string;
}

export interface PairingClientAuthProofResult {
  ok: boolean;
  authProofFrame?: string;
  serverHello?: HelloPayload;
  transcript?: PairingAuthTranscriptDraft;
  transcriptSaltBase64Url?: string;
  error?: PairingClientHandshakeError;
  transportError?: ProtocolTransportFrameError;
  handshakeError?: PairingHandshakeDraftError;
  signatureError?: Ed25519SignatureError;
  huksError?: Ed25519HuksIdentityError;
  frameError?: ProtocolFrameBuildError;
  field?: string;
}

export interface PairingClientAuthenticatedSessionResult {
  ok: boolean;
  transportSession?: ProtocolTransportSession;
  sessionKeys?: ProtocolSessionKeys;
  error?: PairingClientHandshakeError;
  transportError?: ProtocolTransportFrameError;
  keyAgreementError?: X25519KeyAgreementError;
  derivationError?: SessionKeyDerivationError;
  field?: string;
}

export interface PairingServerAuthProofResult {
  ok: boolean;
  error?: PairingClientHandshakeError;
  transportError?: ProtocolTransportFrameError;
  validationError?: PairingAuthProofValidationError;
  field?: string;
}

export interface PairingClientAuthProofSigner {
  signAuthTranscriptWithRef(
    identityPrivateKeyRef: string,
    canonicalTranscript: string
  ): Promise<Ed25519HuksSignatureResult>;
}

export class PairingClientHandshakeSession {
  readonly draft: PairingHandshakeDraft;
  private readonly transportSession: ProtocolHandshakeTransportSession;
  private readonly localEphemeralPrivateKeyValue: string | null;
  private authProofSent: boolean = false;
  private serverAuthProofVerified: boolean = false;
  private serverHelloPayloadValue: HelloPayload | null = null;
  private transcriptSaltBase64UrlValue: string | null = null;

  constructor(draft: PairingHandshakeDraft, localEphemeralPrivateKey?: string) {
    this.draft = draft;
    this.transportSession = new ProtocolHandshakeTransportSession();
    this.localEphemeralPrivateKeyValue = localEphemeralPrivateKey ?? null;
  }

  acceptServerFrame(frame: string) {
    return this.transportSession.acceptTextFrame(frame);
  }

  markAuthProofSent(): void {
    this.authProofSent = true;
  }

  rememberServerHello(serverHello: HelloPayload): void {
    this.serverHelloPayloadValue = cloneHelloPayload(serverHello);
  }

  rememberAuthTranscript(transcript: PairingAuthTranscriptDraft): void {
    this.transcriptSaltBase64UrlValue = sha256Utf8Base64Url(transcript.canonicalTranscript);
  }

  hasSentAuthProof(): boolean {
    return this.authProofSent;
  }

  markServerAuthProofVerified(): void {
    this.serverAuthProofVerified = true;
  }

  hasVerifiedServerAuthProof(): boolean {
    return this.serverAuthProofVerified;
  }

  localEphemeralPrivateKey(): string | null {
    return this.localEphemeralPrivateKeyValue;
  }

  serverHelloPayload(): HelloPayload | null {
    if (this.serverHelloPayloadValue === null) {
      return null;
    }
    return cloneHelloPayload(this.serverHelloPayloadValue);
  }

  transcriptSaltBase64Url(): string | null {
    return this.transcriptSaltBase64UrlValue;
  }
}

export class PairingClientHandshakeSessionService {
  private readonly parser: ProtocolParser = new ProtocolParser();
  private readonly frameBuilder: ProtocolFrameBuilderService = new ProtocolFrameBuilderService();
  private readonly draftService: PairingHandshakeDraftService = new PairingHandshakeDraftService();
  private readonly signatureService: Ed25519SignatureService = new Ed25519SignatureService();
  private readonly keyDerivation: SessionKeyDerivationService = new SessionKeyDerivationService();
  private readonly keyAgreement: X25519KeyAgreementService = new X25519KeyAgreementService();
  private readonly authProofValidation: PairingAuthProofValidator;
  private readonly authProofSigner: PairingClientAuthProofSigner;

  constructor(
    authProofSigner: PairingClientAuthProofSigner = new Ed25519HuksIdentityService(),
    authProofValidation: PairingAuthProofValidator = new PairingAuthProofValidationService()
  ) {
    this.authProofSigner = authProofSigner;
    this.authProofValidation = authProofValidation;
  }

  start(
    draft: PairingHandshakeDraft,
    clientHelloMessageId: string,
    clientHelloCounter: number = 0,
    localEphemeralPrivateKey?: string
  ): PairingClientHandshakeStartResult {
    const clientHello = this.frameBuilder.buildClientHelloFrame(
      draft.clientHelloPayload,
      clientHelloMessageId,
      clientHelloCounter
    );
    if (!clientHello.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.CLIENT_HELLO_BUILD_FAILED,
        frameError: clientHello.error,
        field: clientHello.field
      };
    }
    return {
      ok: true,
      session: new PairingClientHandshakeSession(draft, localEphemeralPrivateKey),
      clientHelloFrame: clientHello.frame
    };
  }

  acceptServerHelloAndSignAuthProof(
    session: PairingClientHandshakeSession,
    serverHelloFrame: string,
    localIdentityPrivateSeed: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): PairingClientAuthProofResult {
    const accepted = session.acceptServerFrame(serverHelloFrame);
    if (!accepted.ok || accepted.envelope === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_FRAME_REJECTED,
        transportError: accepted.error
      };
    }
    if (accepted.outcome !== ProtocolHandshakeFrameOutcome.CONTINUE ||
      accepted.envelope.messageType !== MessageType.SERVER_HELLO) {
      return {
        ok: false,
        error: PairingClientHandshakeError.UNEXPECTED_SERVER_MESSAGE
      };
    }

    const serverHello = this.parser.parseHelloPayload(accepted.envelope.payload);
    if (!serverHello.ok || serverHello.payload === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.INVALID_SERVER_HELLO,
        field: serverHello.field
      };
    }

    const transcript = this.draftService.buildClientAuthTranscriptDraft(session.draft, serverHello.payload);
    if (!transcript.ok || transcript.transcript === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_HELLO_MISMATCH,
        handshakeError: transcript.error,
        field: transcript.field
      };
    }

    const signature = this.signatureService.signMessage(
      localIdentityPrivateSeed,
      transcript.transcript.canonicalTranscript
    );
    if (!signature.ok || signature.signature === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_SIGN_FAILED,
        signatureError: signature.error,
        field: signature.field
      };
    }

    const authProof = this.frameBuilder.buildAuthProofFrame(
      AuthRole.CLIENT,
      transcript.transcript.canonicalTranscript,
      signature.signature,
      authProofMessageId,
      authProofCounter
    );
    if (!authProof.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_BUILD_FAILED,
        frameError: authProof.error,
        field: authProof.field
      };
    }
    session.rememberServerHello(serverHello.payload);
    session.rememberAuthTranscript(transcript.transcript);
    session.markAuthProofSent();

    return {
      ok: true,
      authProofFrame: authProof.frame,
      serverHello: serverHello.payload,
      transcript: transcript.transcript,
      transcriptSaltBase64Url: session.transcriptSaltBase64Url() ?? undefined
    };
  }

  async acceptServerHelloAndSignAuthProofWithRef(
    session: PairingClientHandshakeSession,
    serverHelloFrame: string,
    localIdentityPrivateKeyRef: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): Promise<PairingClientAuthProofResult> {
    const accepted = session.acceptServerFrame(serverHelloFrame);
    if (!accepted.ok || accepted.envelope === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_FRAME_REJECTED,
        transportError: accepted.error
      };
    }
    if (accepted.outcome !== ProtocolHandshakeFrameOutcome.CONTINUE ||
      accepted.envelope.messageType !== MessageType.SERVER_HELLO) {
      return {
        ok: false,
        error: PairingClientHandshakeError.UNEXPECTED_SERVER_MESSAGE
      };
    }

    const serverHello = this.parser.parseHelloPayload(accepted.envelope.payload);
    if (!serverHello.ok || serverHello.payload === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.INVALID_SERVER_HELLO,
        field: serverHello.field
      };
    }

    const transcript = this.draftService.buildClientAuthTranscriptDraft(session.draft, serverHello.payload);
    if (!transcript.ok || transcript.transcript === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_HELLO_MISMATCH,
        handshakeError: transcript.error,
        field: transcript.field
      };
    }

    const signature = await this.authProofSigner.signAuthTranscriptWithRef(
      localIdentityPrivateKeyRef,
      transcript.transcript.canonicalTranscript
    );
    if (!signature.ok || signature.signature === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_SIGN_FAILED,
        huksError: signature.error,
        field: signature.field
      };
    }

    const authProof = this.frameBuilder.buildAuthProofFrame(
      AuthRole.CLIENT,
      transcript.transcript.canonicalTranscript,
      signature.signature,
      authProofMessageId,
      authProofCounter
    );
    if (!authProof.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_BUILD_FAILED,
        frameError: authProof.error,
        field: authProof.field
      };
    }
    session.rememberServerHello(serverHello.payload);
    session.rememberAuthTranscript(transcript.transcript);
    session.markAuthProofSent();

    return {
      ok: true,
      authProofFrame: authProof.frame,
      serverHello: serverHello.payload,
      transcript: transcript.transcript,
      transcriptSaltBase64Url: session.transcriptSaltBase64Url() ?? undefined
    };
  }

  acceptServerHelloAndBuildAuthProof(
    session: PairingClientHandshakeSession,
    serverHelloFrame: string,
    signature: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): PairingClientAuthProofResult {
    const accepted = session.acceptServerFrame(serverHelloFrame);
    if (!accepted.ok || accepted.envelope === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_FRAME_REJECTED,
        transportError: accepted.error
      };
    }
    if (accepted.outcome !== ProtocolHandshakeFrameOutcome.CONTINUE ||
      accepted.envelope.messageType !== MessageType.SERVER_HELLO) {
      return {
        ok: false,
        error: PairingClientHandshakeError.UNEXPECTED_SERVER_MESSAGE
      };
    }

    const serverHello = this.parser.parseHelloPayload(accepted.envelope.payload);
    if (!serverHello.ok || serverHello.payload === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.INVALID_SERVER_HELLO,
        field: serverHello.field
      };
    }

    const transcript = this.draftService.buildClientAuthTranscriptDraft(session.draft, serverHello.payload);
    if (!transcript.ok || transcript.transcript === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_HELLO_MISMATCH,
        handshakeError: transcript.error,
        field: transcript.field
      };
    }

    const authProof = this.frameBuilder.buildAuthProofFrame(
      AuthRole.CLIENT,
      transcript.transcript.canonicalTranscript,
      signature,
      authProofMessageId,
      authProofCounter
    );
    if (!authProof.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_BUILD_FAILED,
        frameError: authProof.error,
        field: authProof.field
      };
    }
    session.rememberServerHello(serverHello.payload);
    session.rememberAuthTranscript(transcript.transcript);
    session.markAuthProofSent();

    return {
      ok: true,
      authProofFrame: authProof.frame,
      serverHello: serverHello.payload,
      transcript: transcript.transcript,
      transcriptSaltBase64Url: session.transcriptSaltBase64Url() ?? undefined
    };
  }

  acceptAuthOkAndCreateTransportSession(
    session: PairingClientHandshakeSession,
    authOkFrame: string,
    sharedSecretBase64Url: string,
    transcriptSaltBase64Url: string
  ): PairingClientAuthenticatedSessionResult {
    if (!session.hasSentAuthProof()) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_NOT_SENT
      };
    }
    if (!session.hasVerifiedServerAuthProof()) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_AUTH_PROOF_REQUIRED
      };
    }

    const accepted = session.acceptServerFrame(authOkFrame);
    if (!accepted.ok || accepted.envelope === undefined ||
      accepted.outcome !== ProtocolHandshakeFrameOutcome.AUTHENTICATED ||
      accepted.envelope.messageType !== MessageType.AUTH_OK) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_OK_REJECTED,
        transportError: accepted.error
      };
    }

    const derived = this.keyDerivation.deriveSessionKeys(sharedSecretBase64Url, transcriptSaltBase64Url);
    if (!derived.ok || derived.keys === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SESSION_KEY_DERIVATION_FAILED,
        derivationError: derived.error,
        field: derived.field
      };
    }

    const sessionKeys: ProtocolSessionKeys = {
      clientToServerKey: derived.keys.clientToServerKey,
      serverToClientKey: derived.keys.serverToClientKey
    };
    return {
      ok: true,
      sessionKeys,
      transportSession: new ProtocolTransportSession(ProtocolSessionState.AUTHENTICATED, sessionKeys)
    };
  }

  acceptServerAuthProof(
    session: PairingClientHandshakeSession,
    serverAuthProofFrame: string
  ): PairingServerAuthProofResult {
    if (!session.hasSentAuthProof()) {
      return { ok: false, error: PairingClientHandshakeError.AUTH_PROOF_NOT_SENT };
    }
    const accepted = session.acceptServerFrame(serverAuthProofFrame);
    if (!accepted.ok || accepted.envelope === undefined ||
      accepted.outcome !== ProtocolHandshakeFrameOutcome.CONTINUE ||
      accepted.envelope.messageType !== MessageType.AUTH_PROOF) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_AUTH_PROOF_REJECTED,
        transportError: accepted.error
      };
    }
    const payload = this.parser.parseAuthProofPayload(accepted.envelope.payload);
    const serverHello = session.serverHelloPayload();
    if (!payload.ok || payload.payload === undefined || serverHello === null) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_AUTH_PROOF_INVALID,
        field: payload.field ?? 'serverHello'
      };
    }
    const transcript = this.draftService.buildServerAuthTranscriptDraft(session.draft, serverHello);
    if (!transcript.ok || transcript.transcript === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_AUTH_PROOF_INVALID,
        field: transcript.field
      };
    }
    const verified = this.authProofValidation.verifyPayloadSignatureAgainstTranscript(
      payload.payload,
      AuthRole.SERVER,
      transcript.transcript,
      session.draft.remoteIdentityPublicKey
    );
    if (!verified.ok) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SERVER_AUTH_PROOF_INVALID,
        validationError: verified.error,
        field: verified.field
      };
    }
    session.markServerAuthProofVerified();
    return { ok: true };
  }

  acceptAuthOkAndCreateTransportSessionFromEphemeral(
    session: PairingClientHandshakeSession,
    authOkFrame: string,
    transcriptSaltBase64Url: string
  ): PairingClientAuthenticatedSessionResult {
    if (!session.hasSentAuthProof()) {
      return {
        ok: false,
        error: PairingClientHandshakeError.AUTH_PROOF_NOT_SENT
      };
    }

    const localEphemeralPrivateKey = session.localEphemeralPrivateKey();
    if (localEphemeralPrivateKey === null) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED,
        field: 'localEphemeralPrivateKey'
      };
    }

    const serverHello = session.serverHelloPayload();
    if (serverHello === null) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED,
        field: 'serverHello'
      };
    }

    const sharedSecret = this.keyAgreement.deriveSharedSecret(
      localEphemeralPrivateKey,
      serverHello.ephemeralPublicKey
    );
    if (!sharedSecret.ok || sharedSecret.sharedSecret === undefined) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SHARED_SECRET_DERIVATION_FAILED,
        keyAgreementError: sharedSecret.error,
        field: sharedSecret.field
      };
    }

    return this.acceptAuthOkAndCreateTransportSession(
      session,
      authOkFrame,
      sharedSecret.sharedSecret,
      transcriptSaltBase64Url
    );
  }

  acceptAuthOkAndCreateTransportSessionFromRememberedTranscript(
    session: PairingClientHandshakeSession,
    authOkFrame: string
  ): PairingClientAuthenticatedSessionResult {
    const transcriptSaltBase64Url = session.transcriptSaltBase64Url();
    if (transcriptSaltBase64Url === null) {
      return {
        ok: false,
        error: PairingClientHandshakeError.SESSION_KEY_DERIVATION_FAILED,
        field: 'transcriptSalt'
      };
    }
    return this.acceptAuthOkAndCreateTransportSessionFromEphemeral(
      session,
      authOkFrame,
      transcriptSaltBase64Url
    );
  }
}

function cloneHelloPayload(payload: HelloPayload): HelloPayload {
  const clone: HelloPayload = {
    spaceId: payload.spaceId,
    deviceId: payload.deviceId,
    identityPublicKey: payload.identityPublicKey,
    ephemeralPublicKey: payload.ephemeralPublicKey,
    capabilities: payload.capabilities.slice()
  };
  if (payload.pairingContext !== undefined) {
    clone.pairingContext = payload.pairingContext;
  }
  if (payload.pairingProof !== undefined) {
    clone.pairingProof = payload.pairingProof;
  }
  return clone;
}
