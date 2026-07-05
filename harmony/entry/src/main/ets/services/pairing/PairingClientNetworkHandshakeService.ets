import { ProtocolTransportSession } from '../transport/ProtocolTransportSession';
import {
  PairingClientAuthenticatedSessionResult,
  PairingClientAuthProofResult,
  PairingClientHandshakeError,
  PairingClientHandshakeSession,
  PairingClientHandshakeSessionService
} from './PairingClientHandshakeSessionService';
import { PairingHandshakeDraft } from './PairingHandshakeDraftService';
import { Ed25519HuksIdentityError } from '../crypto/Ed25519HuksIdentityService';

export enum PairingClientNetworkHandshakePhase {
  IDLE = 'idle',
  CLIENT_HELLO_READY = 'clientHelloReady',
  WAITING_AUTH_OK = 'waitingAuthOk',
  AUTHENTICATED = 'authenticated',
  FAILED = 'failed'
}

export enum PairingClientNetworkHandshakeError {
  INVALID_PHASE = 'invalidPhase',
  START_FAILED = 'startFailed',
  AUTH_PROOF_FAILED = 'authProofFailed',
  AUTH_OK_FAILED = 'authOkFailed'
}

export interface PairingClientNetworkHandshakeStartResult {
  ok: boolean;
  phase: PairingClientNetworkHandshakePhase;
  outgoingFrame?: string;
  error?: PairingClientNetworkHandshakeError;
  handshakeError?: PairingClientHandshakeError;
  field?: string;
}

export interface PairingClientNetworkAuthProofResult {
  ok: boolean;
  phase: PairingClientNetworkHandshakePhase;
  outgoingFrame?: string;
  transcriptSaltBase64Url?: string;
  error?: PairingClientNetworkHandshakeError;
  handshakeError?: PairingClientHandshakeError;
  huksError?: Ed25519HuksIdentityError;
  field?: string;
}

export interface PairingClientNetworkAuthenticatedResult {
  ok: boolean;
  phase: PairingClientNetworkHandshakePhase;
  transportSession?: ProtocolTransportSession;
  error?: PairingClientNetworkHandshakeError;
  handshakeError?: PairingClientHandshakeError;
  field?: string;
}

export class PairingClientNetworkHandshakeService {
  private readonly handshake: PairingClientHandshakeSessionService;
  private phaseValue: PairingClientNetworkHandshakePhase = PairingClientNetworkHandshakePhase.IDLE;
  private session: PairingClientHandshakeSession | null = null;

  constructor(handshake: PairingClientHandshakeSessionService = new PairingClientHandshakeSessionService()) {
    this.handshake = handshake;
  }

  phase(): PairingClientNetworkHandshakePhase {
    return this.phaseValue;
  }

  start(
    draft: PairingHandshakeDraft,
    clientHelloMessageId: string,
    clientHelloCounter: number = 0,
    localEphemeralPrivateKey?: string
  ): PairingClientNetworkHandshakeStartResult {
    if (this.phaseValue !== PairingClientNetworkHandshakePhase.IDLE &&
      this.phaseValue !== PairingClientNetworkHandshakePhase.FAILED) {
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.INVALID_PHASE
      };
    }

    const started = this.handshake.start(draft, clientHelloMessageId, clientHelloCounter, localEphemeralPrivateKey);
    if (!started.ok || started.session === undefined || started.clientHelloFrame === undefined) {
      this.fail();
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.START_FAILED,
        handshakeError: started.error,
        field: started.field
      };
    }

    this.session = started.session;
    this.phaseValue = PairingClientNetworkHandshakePhase.CLIENT_HELLO_READY;
    return {
      ok: true,
      phase: this.phaseValue,
      outgoingFrame: started.clientHelloFrame
    };
  }

  acceptServerHelloAndBuildAuthProof(
    serverHelloFrame: string,
    signature: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): PairingClientNetworkAuthProofResult {
    if (this.session === null || this.phaseValue !== PairingClientNetworkHandshakePhase.CLIENT_HELLO_READY) {
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.INVALID_PHASE
      };
    }

    const proof: PairingClientAuthProofResult = this.handshake.acceptServerHelloAndBuildAuthProof(
      this.session,
      serverHelloFrame,
      signature,
      authProofMessageId,
      authProofCounter
    );
    if (!proof.ok || proof.authProofFrame === undefined) {
      this.fail();
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.AUTH_PROOF_FAILED,
        handshakeError: proof.error,
        field: proof.field
      };
    }

    this.phaseValue = PairingClientNetworkHandshakePhase.WAITING_AUTH_OK;
    return {
      ok: true,
      phase: this.phaseValue,
      outgoingFrame: proof.authProofFrame,
      transcriptSaltBase64Url: proof.transcriptSaltBase64Url
    };
  }

  acceptServerHelloAndSignAuthProof(
    serverHelloFrame: string,
    localIdentityPrivateSeed: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): PairingClientNetworkAuthProofResult {
    if (this.session === null || this.phaseValue !== PairingClientNetworkHandshakePhase.CLIENT_HELLO_READY) {
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.INVALID_PHASE
      };
    }

    const proof: PairingClientAuthProofResult = this.handshake.acceptServerHelloAndSignAuthProof(
      this.session,
      serverHelloFrame,
      localIdentityPrivateSeed,
      authProofMessageId,
      authProofCounter
    );
    if (!proof.ok || proof.authProofFrame === undefined) {
      this.fail();
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.AUTH_PROOF_FAILED,
        handshakeError: proof.error,
        field: proof.field
      };
    }

    this.phaseValue = PairingClientNetworkHandshakePhase.WAITING_AUTH_OK;
    return {
      ok: true,
      phase: this.phaseValue,
      outgoingFrame: proof.authProofFrame,
      transcriptSaltBase64Url: proof.transcriptSaltBase64Url
    };
  }

  async acceptServerHelloAndSignAuthProofWithRef(
    serverHelloFrame: string,
    localIdentityPrivateKeyRef: string,
    authProofMessageId: string,
    authProofCounter: number = 2
  ): Promise<PairingClientNetworkAuthProofResult> {
    if (this.session === null || this.phaseValue !== PairingClientNetworkHandshakePhase.CLIENT_HELLO_READY) {
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.INVALID_PHASE
      };
    }

    const proof: PairingClientAuthProofResult = await this.handshake.acceptServerHelloAndSignAuthProofWithRef(
      this.session,
      serverHelloFrame,
      localIdentityPrivateKeyRef,
      authProofMessageId,
      authProofCounter
    );
    if (!proof.ok || proof.authProofFrame === undefined) {
      this.fail();
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.AUTH_PROOF_FAILED,
        handshakeError: proof.error,
        huksError: proof.huksError,
        field: proof.field
      };
    }

    this.phaseValue = PairingClientNetworkHandshakePhase.WAITING_AUTH_OK;
    return {
      ok: true,
      phase: this.phaseValue,
      outgoingFrame: proof.authProofFrame,
      transcriptSaltBase64Url: proof.transcriptSaltBase64Url
    };
  }

  acceptAuthOkAndCreateTransportSession(
    authOkFrame: string,
    sharedSecretBase64Url: string,
    transcriptSaltBase64Url: string
  ): PairingClientNetworkAuthenticatedResult {
    if (this.session === null || this.phaseValue !== PairingClientNetworkHandshakePhase.WAITING_AUTH_OK) {
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.INVALID_PHASE
      };
    }

    const authenticated: PairingClientAuthenticatedSessionResult = this.handshake.acceptAuthOkAndCreateTransportSession(
      this.session,
      authOkFrame,
      sharedSecretBase64Url,
      transcriptSaltBase64Url
    );
    if (!authenticated.ok || authenticated.transportSession === undefined) {
      this.fail();
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.AUTH_OK_FAILED,
        handshakeError: authenticated.error,
        field: authenticated.field
      };
    }

    this.phaseValue = PairingClientNetworkHandshakePhase.AUTHENTICATED;
    return {
      ok: true,
      phase: this.phaseValue,
      transportSession: authenticated.transportSession
    };
  }

  acceptAuthOkAndCreateTransportSessionFromEphemeral(
    authOkFrame: string,
    transcriptSaltBase64Url: string
  ): PairingClientNetworkAuthenticatedResult {
    if (this.session === null || this.phaseValue !== PairingClientNetworkHandshakePhase.WAITING_AUTH_OK) {
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.INVALID_PHASE
      };
    }

    const authenticated: PairingClientAuthenticatedSessionResult =
      this.handshake.acceptAuthOkAndCreateTransportSessionFromEphemeral(
        this.session,
        authOkFrame,
        transcriptSaltBase64Url
      );
    if (!authenticated.ok || authenticated.transportSession === undefined) {
      this.fail();
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.AUTH_OK_FAILED,
        handshakeError: authenticated.error,
        field: authenticated.field
      };
    }

    this.phaseValue = PairingClientNetworkHandshakePhase.AUTHENTICATED;
    return {
      ok: true,
      phase: this.phaseValue,
      transportSession: authenticated.transportSession
    };
  }

  acceptAuthOkAndCreateTransportSessionFromRememberedTranscript(
    authOkFrame: string
  ): PairingClientNetworkAuthenticatedResult {
    if (this.session === null || this.phaseValue !== PairingClientNetworkHandshakePhase.WAITING_AUTH_OK) {
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.INVALID_PHASE
      };
    }

    const authenticated: PairingClientAuthenticatedSessionResult =
      this.handshake.acceptAuthOkAndCreateTransportSessionFromRememberedTranscript(
        this.session,
        authOkFrame
      );
    if (!authenticated.ok || authenticated.transportSession === undefined) {
      this.fail();
      return {
        ok: false,
        phase: this.phaseValue,
        error: PairingClientNetworkHandshakeError.AUTH_OK_FAILED,
        handshakeError: authenticated.error,
        field: authenticated.field
      };
    }

    this.phaseValue = PairingClientNetworkHandshakePhase.AUTHENTICATED;
    return {
      ok: true,
      phase: this.phaseValue,
      transportSession: authenticated.transportSession
    };
  }

  reset(): void {
    this.phaseValue = PairingClientNetworkHandshakePhase.IDLE;
    this.session = null;
  }

  private fail(): void {
    this.phaseValue = PairingClientNetworkHandshakePhase.FAILED;
    this.session = null;
  }
}
