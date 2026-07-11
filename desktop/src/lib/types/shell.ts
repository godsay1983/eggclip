export type ConnectionState =
  | "offline"
  | "connecting"
  | "online"
  | "authFailed"
  | "paused";

export interface DeviceSummary {
  id: string;
  name: string;
  state: ConnectionState;
  trustKind: "trusted" | "poc" | "placeholder";
  shortFingerprint: string;
  lastSeen: string;
  endpoint?: string;
  note: string;
}

export interface ClipboardPreview {
  id: string;
  title: string;
  text: string;
  preview: string;
  source: string;
  receivedAt: string;
  canCopy: boolean;
}

export type OutboundSyncState =
  | "idle"
  | "local"
  | "waiting"
  | "pending"
  | "sent"
  | "failed"
  | "paused";

export interface OutboundSyncStatus {
  state: OutboundSyncState;
  title: string;
  description: string;
  updatedAt: string;
}

export interface HistorySummary {
  used: number;
  limit: number;
  items: HistoryItemSummary[];
}

export interface HistoryItemSummary {
  id: string;
  title: string;
  preview: string;
  source: string;
  receivedAt: string;
  contentLength: number;
  text: string | null;
  canCopy: boolean;
}

export type PocRejectionReason =
  | "frameTooLarge"
  | "invalidMessage"
  | "emptyText"
  | "textTooLarge"
  | "binaryUnsupported"
  | "authenticatedFrameRejected"
  | "pairingClientHelloRejected"
  | "pairingInvitationMissing"
  | "pairingInvitationExpired"
  | "pairingInvitationConsumed"
  | "pairingAuthProofRejected"
  | "pairingAuthSignatureRejected"
  | "pairingServerStateMissing"
  | "pairingInternalError";

export interface PocDiagnostics {
  receivedFrames: number;
  acceptedItems: number;
  rejectedFrames: number;
  lastRejection: PocRejectionReason | null;
}

export interface PocNetworkAddressSummary {
  interfaceName: string;
  address: string;
  isTunnel: boolean;
}

export interface PocTransportSummary {
  state: "running" | "stopped" | "failed";
  port: number;
  discoveryPublished: boolean;
  networkAddresses: PocNetworkAddressSummary[];
  connectedPeers: number;
  lastError: string | null;
}

export interface PocRecentEndpoint {
  host: string;
  port: number;
  label: string;
  connectedAt: string;
  connectedAtMs: number;
}

export interface SyncSpaceSummary {
  id: string;
  displayName: string;
  keyVersion: number;
  shortId: string;
  keyRefKind: "credential" | "unknown";
  createdAt: string;
}

export interface PairingInvitationSummary {
  invitationId: string;
  spaceId: string;
  spaceDisplayName: string;
  invitationString: string;
  qrSvg: string;
  expiresAt: string;
  expiresInSeconds: number;
  issuerDeviceName: string;
  issuerDeviceId: string;
  issuerShortFingerprint: string;
  confirmationCode: string;
}

export interface SpaceHmacDiagnosticSummary {
  spaceId: string;
  spaceDisplayName: string;
  confirmationCode: string;
}

export interface SyncSpaceState {
  state: "idle" | "loading" | "creating" | "inviting" | "copyingInvitation" | "ready" | "error";
  spaces: SyncSpaceSummary[];
  activeSpaceId: string | null;
  hmacDiagnostic: SpaceHmacDiagnosticSummary | null;
  invitation: PairingInvitationSummary | null;
  errorMessage: string | null;
  invitationCopiedAt: string | null;
}

export interface ShellSnapshot {
  connection: {
    state: ConnectionState;
    title: string;
    description: string;
  };
  current: ClipboardPreview | null;
  outbound: OutboundSyncStatus;
  devices: DeviceSummary[];
  history: HistorySummary;
  pocDiagnostics: PocDiagnostics;
  pocTransport: PocTransportSummary;
  lastPocEndpoint: PocRecentEndpoint | null;
  syncSpace: SyncSpaceState;
  syncEnabled: boolean;
}
