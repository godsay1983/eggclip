export type ConnectionState =
  | "offline"
  | "connecting"
  | "online"
  | "authFailed"
  | "paused";

export interface DeviceSummary {
  id: string;
  spaceId?: string;
  name: string;
  nameOrigin?: "generated" | "custom";
  state: ConnectionState;
  trustKind: "trusted" | "poc" | "placeholder";
  shortFingerprint: string;
  endpoint?: string;
  pairedAtMs?: number | null;
  lastSeenAtMs?: number | null;
}

export interface TrustedDeviceRemovalSummary {
  deviceId: string;
  spaceId: string;
  keyVersion: number;
  deliveredPeers: number;
}

export interface ClipboardPreview {
  id: string;
  text: string;
  preview: string;
  byteLength: number;
  sourceKind: "local" | "localMonitor" | "poc" | "trusted";
  sourceDevice?: string;
  receivedAtMs: number;
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
  title: UiMessageDescriptor;
  description: UiMessageDescriptor;
  updatedAtMs: number | null;
}

export interface HistorySummary {
  used: number;
  limit: number;
  items: HistoryItemSummary[];
}

export interface HistoryItemSummary {
  id: string;
  preview: string;
  originDeviceId: string;
  receivedAtMs: number;
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

export interface MdnsServiceCandidateSummary {
  instanceId: string;
  deviceId: string;
  addresses: string[];
  port: number;
  protocolVersion: number;
  capabilities: string[];
}

export interface PocTransportSummary {
  state: "running" | "stopped" | "failed";
  port: number;
  discoveryPublished: boolean;
  networkAddresses: PocNetworkAddressSummary[];
  discoveredServices: MdnsServiceCandidateSummary[];
  connectedPeers: number;
  lastError: "acceptFailed" | "handshakeFailed" | null;
}

export interface PocRecentEndpoint {
  host: string;
  port: number;
  label: string;
  connectedAtMs: number;
}

export interface SyncSpaceSummary {
  id: string;
  displayName: string;
  nameOrigin: "generated" | "custom";
  keyVersion: number;
  shortId: string;
  keyRefKind: "credential" | "unknown";
  createdAtMs: number;
  localRole: "owner" | "member";
}

export interface PairingInvitationSummary {
  invitationId: string;
  spaceId: string;
  spaceDisplayName: string;
  spaceNameOrigin: "generated" | "custom";
  qrSvg: string;
  expiresAtMs: number;
  expiresInSeconds: number;
  issuerDeviceName: string;
  issuerDeviceId: string;
  issuerShortFingerprint: string;
  confirmationCode: string;
}

export interface SpaceHmacDiagnosticSummary {
  spaceId: string;
  spaceDisplayName: string;
  spaceNameOrigin: "generated" | "custom";
  confirmationCode: string;
}

export interface SyncSpaceState {
  state: "idle" | "loading" | "creating" | "inviting" | "copyingInvitation" | "ready" | "error";
  spaces: SyncSpaceSummary[];
  activeSpaceId: string | null;
  hmacDiagnostic: SpaceHmacDiagnosticSummary | null;
  invitation: PairingInvitationSummary | null;
  errorMessage: UiMessageDescriptor | null;
  invitationCopiedAtMs: number | null;
}

export interface ShellSnapshot {
  connection: {
    state: ConnectionState;
    title: UiMessageDescriptor;
    description: UiMessageDescriptor;
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
import type { UiMessageDescriptor } from "$lib/i18n";
