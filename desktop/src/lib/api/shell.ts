import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { uiMessage } from "$lib/i18n";
import type {
  ClipboardPreview,
  HistoryItemSummary,
  PairingInvitationSummary,
  PocDiagnostics,
  PocRecentEndpoint,
  PocTransportSummary,
  ShellSnapshot,
  SpaceHmacDiagnosticSummary,
  SyncSpaceSummary,
  DeviceSummary,
  TrustedDeviceRemovalSummary,
} from "$lib/types/shell";

interface ClipboardTextItem {
  text: string;
  byteLen: number;
  digest: number;
}

type ClipboardTextError =
  | "empty"
  | {
      tooLarge: {
        actualBytes: number;
        maxBytes: number;
      };
    };

interface ClipboardReadResult {
  item: ClipboardTextItem | null;
  error: ClipboardTextError | null;
}

interface ClipboardMonitorEvent {
  item: ClipboardTextItem;
}

interface PocClipboardTextEvent {
  peer: string;
  item: ClipboardTextItem;
}

interface PocTransportStatus {
  state: "running" | "stopped" | "failed";
  bindAddress: string;
  port: number;
  discoveryPublished: boolean;
  networkAddresses: PocNetworkAddress[];
  discoveredServices: MdnsServiceCandidateDto[];
  connectedPeers: number;
  diagnostics: PocDiagnostics;
  lastError: string | null;
}

interface MdnsServiceCandidateDto {
  instanceId: string;
  deviceId: string;
  addresses: string[];
  port: number;
  protocolVersion: number;
  capabilities: string[];
}

interface PocNetworkAddress {
  interfaceName: string;
  address: string;
  isTunnel: boolean;
}

interface PocPeerEvent {
  peer: string;
}

interface AuthenticatedLocalBroadcastEvent {
  status:
    | "sent"
    | "skippedNoAuthenticatedPeer"
    | "skippedAmbiguousSpace"
    | "skippedByPolicy"
    | "failed";
  sentPeers: number;
}

export interface AuthenticatedClipboardTextEvent {
  peer: string;
  itemId: string;
  originDeviceId: string;
  originSeq: number;
  item: ClipboardTextItem;
}

interface HistoryItemSummaryDto {
  id: string;
  preview: string;
  originDeviceId: string;
  receivedAtMs: number;
  contentLength: number;
  text: string | null;
  canCopy: boolean;
}

interface PocRecentEndpointDto {
  host: string;
  port: number;
  connectedAtMs: number;
}

interface SyncSpaceSummaryDto {
  spaceId: string;
  displayName: string;
  keyVersion: number;
  spaceKeyRef: string;
  createdAtMs: number;
  localRole: "owner" | "member";
}

export interface SyncSpaceDeletionSummary {
  deletedSpaceId: string;
  activeSpaceId: string;
  credentialDeleted: boolean;
}

export interface MemberSpaceLeaveSummary {
  leftSpaceId: string;
  activeSpaceId: string;
  credentialDeleted: boolean;
}

interface PairingInvitationSummaryDto {
  invitationId: string;
  spaceId: string;
  spaceDisplayName: string;
  qrSvg: string;
  expiresAtMs: number;
  expiresInSeconds: number;
  issuerDeviceName: string;
  issuerDeviceId: string;
  issuerShortFingerprint: string;
  confirmationCode: string;
}

interface SpaceHmacDiagnosticSummaryDto {
  spaceId: string;
  spaceDisplayName: string;
  confirmationCode: string;
}

interface TrustedDeviceSummaryDto {
  deviceId: string;
  spaceId: string;
  displayName: string;
  connectionState: DeviceSummary["state"];
  shortFingerprint: string;
  pairedAtMs: number | null;
  lastSeenAtMs: number | null;
  endpoint: string | null;
}

interface AuthenticatedConnectionStateEvent {
  peer: string;
  deviceId: string;
  spaceId: string;
  state: "online" | "offline";
  reason: string;
}

export interface SpaceKeyRotatedEvent {
  spaceId: string;
  keyVersion: number;
}

export function createInitialShellSnapshot(): ShellSnapshot {
  return {
    connection: {
      state: "offline",
      title: uiMessage("connection.waitingTitle"),
      description: uiMessage("connection.waitingDescription"),
    },
    current: null,
    outbound: {
      state: "idle",
      title: uiMessage("clipboard.waitingTitle"),
      description: uiMessage("clipboard.waitingDescription"),
      updatedAtMs: null,
    },
    devices: [
      {
        id: "placeholder",
        name: "",
        state: "offline",
        trustKind: "placeholder",
        shortFingerprint: "",
      },
    ],
    history: {
      used: 0,
      limit: 50,
      items: [],
    },
    pocDiagnostics: {
      receivedFrames: 0,
      acceptedItems: 0,
      rejectedFrames: 0,
      lastRejection: null,
    },
    pocTransport: {
      state: "stopped",
      port: 0,
      discoveryPublished: false,
      networkAddresses: [],
      discoveredServices: [],
      connectedPeers: 0,
      lastError: null,
    },
    lastPocEndpoint: null,
    syncSpace: {
      state: "idle",
      spaces: [],
      activeSpaceId: null,
      hmacDiagnostic: null,
      invitation: null,
      errorMessage: null,
      invitationCopiedAtMs: null,
    },
    syncEnabled: true,
  };
}

export async function readSystemClipboardText(): Promise<ClipboardPreview> {
  const result = await invoke<ClipboardReadResult>("read_clipboard_text");
  if (result.item) {
    return toClipboardPreview(result.item, "local");
  }
  throw new Error(formatClipboardError(result.error));
}

export async function writeSystemClipboardText(text: string): Promise<void> {
  await invoke("write_clipboard_text", { text });
}

export async function clearClipboardHistory(): Promise<number> {
  return invoke<number>("clear_clipboard_history");
}

export async function captureClipboardHistoryText(
  text: string,
): Promise<HistoryItemSummary | null> {
  const item = await invoke<HistoryItemSummaryDto | null>("capture_clipboard_history_text", {
    text,
  });
  return item ? toHistoryItemSummary(item) : null;
}

export async function deleteClipboardHistoryItem(itemId: string): Promise<boolean> {
  return invoke<boolean>("delete_clipboard_history_item", { itemId });
}

export async function getClipboardHistoryUsed(): Promise<number> {
  return invoke<number>("get_clipboard_history_used");
}

export async function listClipboardHistoryPreview(): Promise<HistoryItemSummary[]> {
  const items = await invoke<HistoryItemSummaryDto[]>("list_clipboard_history_preview");
  return items.map(toHistoryItemSummary);
}

export async function sendPocClipboardText(text: string): Promise<number> {
  return invoke<number>("send_poc_clipboard_text", { text });
}

export async function sendAuthenticatedClipboardText(text: string): Promise<number> {
  return invoke<number>("send_authenticated_clipboard_text", { text });
}

export async function connectPocPeer(host: string, port: number): Promise<PocRecentEndpoint> {
  const endpoint = await invoke<PocRecentEndpointDto>("connect_poc_peer", { host, port });
  return toPocRecentEndpoint(endpoint);
}

export async function disconnectAllPocPeers(): Promise<number> {
  return invoke<number>("disconnect_all_poc_peers");
}

export async function loadPocRecentEndpoint(): Promise<PocRecentEndpoint | null> {
  const endpoint = await invoke<PocRecentEndpointDto | null>("load_poc_recent_endpoint");
  return endpoint ? toPocRecentEndpoint(endpoint) : null;
}

export async function createLocalSyncSpace(displayName: string): Promise<SyncSpaceSummary> {
  const space = await invoke<SyncSpaceSummaryDto>("create_local_sync_space", { displayName });
  return toSyncSpaceSummary(space);
}

export async function listLocalSyncSpaces(): Promise<SyncSpaceSummary[]> {
  const spaces = await invoke<SyncSpaceSummaryDto[]>("list_local_sync_spaces");
  return spaces.map(toSyncSpaceSummary);
}

export async function deleteLocalSyncSpace(
  spaceId: string,
): Promise<SyncSpaceDeletionSummary> {
  return invoke<SyncSpaceDeletionSummary>("delete_local_sync_space", { spaceId });
}

export async function leaveMemberSyncSpace(
  spaceId: string,
): Promise<MemberSpaceLeaveSummary> {
  return invoke<MemberSpaceLeaveSummary>("leave_member_sync_space", { spaceId });
}

export async function loadActiveSyncSpaceId(): Promise<string | null> {
  return invoke<string | null>("load_active_sync_space_id");
}

export async function selectActiveSyncSpace(spaceId: string): Promise<SyncSpaceSummary> {
  const space = await invoke<SyncSpaceSummaryDto>("select_active_sync_space", { spaceId });
  return toSyncSpaceSummary(space);
}

export async function runSpaceHmacDiagnostic(): Promise<SpaceHmacDiagnosticSummary> {
  return invoke<SpaceHmacDiagnosticSummaryDto>("run_space_hmac_diagnostic");
}

export async function listTrustedDevices(): Promise<DeviceSummary[]> {
  const devices = await invoke<TrustedDeviceSummaryDto[]>("list_trusted_devices");
  return devices.map(toTrustedDeviceSummary);
}

export async function renameTrustedDevice(deviceId: string, displayName: string): Promise<DeviceSummary> {
  const device = await invoke<TrustedDeviceSummaryDto>("rename_trusted_device", {
    deviceId,
    displayName,
  });
  return toTrustedDeviceSummary(device);
}

export async function removeTrustedDevice(deviceId: string): Promise<TrustedDeviceRemovalSummary> {
  return invoke<TrustedDeviceRemovalSummary>("remove_trusted_device", { deviceId });
}

export async function ensureDefaultSyncSpace(): Promise<SyncSpaceSummary> {
  const space = await invoke<SyncSpaceSummaryDto>("ensure_default_sync_space");
  return toSyncSpaceSummary(space);
}

export async function createPairingInvitation(
  spaceId: string,
): Promise<PairingInvitationSummary> {
  const invitation = await invoke<PairingInvitationSummaryDto>("create_pairing_invitation", {
    spaceId,
  });
  return toPairingInvitationSummary(invitation);
}

export async function copyPairingInvitation(invitationId: string): Promise<void> {
  await invoke("copy_pairing_invitation", {
    invitationId,
  });
}

export async function startPocTransport(): Promise<PocTransportSummary> {
  const status = await invoke<PocTransportStatus>("start_poc_transport", {
    port: null,
  });
  return toPocTransportSummary(status);
}

export async function getPocTransportStatus(): Promise<PocTransportSummary> {
  const status = await invoke<PocTransportStatus>("get_poc_transport_status");
  return toPocTransportSummary(status);
}

export async function onLocalClipboardText(
  handler: (preview: ClipboardPreview) => void,
): Promise<() => void> {
  const unlisten = await listen<ClipboardMonitorEvent>(
    "clipboard://local-text",
    (event) => {
      handler(toClipboardPreview(event.payload.item, "localMonitor"));
    },
  );

  return unlisten;
}

export async function onAuthenticatedLocalBroadcast(
  handler: (event: AuthenticatedLocalBroadcastEvent) => void,
): Promise<() => void> {
  return listen<AuthenticatedLocalBroadcastEvent>(
    "transport://authenticated-local-broadcast",
    (event) => {
      handler(event.payload);
    },
  );
}

export async function onAuthenticatedConnection(
  callback: (event: AuthenticatedConnectionStateEvent) => void,
) {
  return listen<AuthenticatedConnectionStateEvent>(
    "transport://authenticated-connection",
    (event) => callback(event.payload),
  );
}

export async function onAuthenticatedClipboardText(
  handler: (preview: ClipboardPreview, event: AuthenticatedClipboardTextEvent) => void,
): Promise<() => void> {
  return listen<AuthenticatedClipboardTextEvent>(
    "transport://authenticated-clipboard-text",
    (event) => {
      handler(toAuthenticatedClipboardPreview(event.payload), event.payload);
    },
  );
}

export async function onSpaceKeyRotated(
  handler: (event: SpaceKeyRotatedEvent) => void,
): Promise<() => void> {
  return listen<SpaceKeyRotatedEvent>("transport://space-key-rotated", (event) => {
    handler(event.payload);
  });
}

export async function onPocClipboardText(
  handler: (preview: ClipboardPreview, peer: string) => void,
): Promise<() => void> {
  const unlisten = await listen<PocClipboardTextEvent>(
    "transport://poc-clipboard-text",
    (event) => {
      handler(
        toClipboardPreview(event.payload.item, "poc", event.payload.peer),
        event.payload.peer,
      );
    },
  );

  return unlisten;
}

export async function onPocPeerConnected(
  handler: (peer: string) => void,
): Promise<() => void> {
  return listen<PocPeerEvent>("transport://poc-peer-connected", (event) => {
    handler(event.payload.peer);
  });
}

export async function onPocPeerDisconnected(
  handler: (peer: string) => void,
): Promise<() => void> {
  return listen<PocPeerEvent>("transport://poc-peer-disconnected", (event) => {
    handler(event.payload.peer);
  });
}

export async function onPocDiscoveryError(
  handler: (message: string) => void,
): Promise<() => void> {
  return listen<string>("discovery://poc-error", (event) => {
    handler(event.payload);
  });
}

export async function onPocDiagnostics(
  handler: (diagnostics: PocDiagnostics) => void,
): Promise<() => void> {
  return listen<PocDiagnostics>("transport://poc-diagnostics", (event) => {
    handler(event.payload);
  });
}

function toPocTransportSummary(status: PocTransportStatus): PocTransportSummary {
  return {
    state: status.state,
    port: status.port,
    discoveryPublished: status.discoveryPublished,
    networkAddresses: status.networkAddresses.map((item) => ({
      interfaceName: item.interfaceName,
      address: item.address,
      isTunnel: item.isTunnel,
    })),
    discoveredServices: status.discoveredServices.map((item) => ({
      instanceId: item.instanceId,
      deviceId: item.deviceId,
      addresses: [...item.addresses],
      port: item.port,
      protocolVersion: item.protocolVersion,
      capabilities: [...item.capabilities],
    })),
    connectedPeers: status.connectedPeers,
    lastError: status.lastError,
  };
}

function toPocRecentEndpoint(endpoint: PocRecentEndpointDto): PocRecentEndpoint {
  return {
    host: endpoint.host,
    port: endpoint.port,
    label: `${endpoint.host}:${endpoint.port}`,
    connectedAtMs: endpoint.connectedAtMs,
  };
}

function toTrustedDeviceSummary(device: TrustedDeviceSummaryDto): DeviceSummary {
  return {
    id: device.deviceId,
    spaceId: device.spaceId,
    name: device.displayName,
    state: device.connectionState,
    trustKind: "trusted",
    shortFingerprint: device.shortFingerprint,
    endpoint: device.endpoint ?? undefined,
    pairedAtMs: device.pairedAtMs,
    lastSeenAtMs: device.lastSeenAtMs,
  };
}

function toSyncSpaceSummary(space: SyncSpaceSummaryDto): SyncSpaceSummary {
  return {
    id: space.spaceId,
    displayName: space.displayName,
    keyVersion: space.keyVersion,
    shortId: space.spaceId.slice(-8),
    keyRefKind: space.spaceKeyRef.startsWith("credential://") ? "credential" : "unknown",
    createdAtMs: space.createdAtMs,
    localRole: space.localRole,
  };
}

function toPairingInvitationSummary(
  invitation: PairingInvitationSummaryDto,
): PairingInvitationSummary {
  return {
    invitationId: invitation.invitationId,
    spaceId: invitation.spaceId,
    spaceDisplayName: invitation.spaceDisplayName,
    qrSvg: invitation.qrSvg,
    expiresAtMs: invitation.expiresAtMs,
    expiresInSeconds: invitation.expiresInSeconds,
    issuerDeviceName: invitation.issuerDeviceName,
    issuerDeviceId: invitation.issuerDeviceId,
    issuerShortFingerprint: invitation.issuerShortFingerprint,
    confirmationCode: invitation.confirmationCode,
  };
}

function toClipboardPreview(
  item: ClipboardTextItem,
  sourceKind: ClipboardPreview["sourceKind"],
  sourceDevice?: string,
): ClipboardPreview {
  return {
    id: `local-${item.digest}`,
    text: item.text,
    preview: trimPreview(item.text),
    byteLength: item.byteLen,
    sourceKind,
    sourceDevice,
    receivedAtMs: Date.now(),
    canCopy: true,
  };
}

export function toAuthenticatedClipboardPreview(
  event: AuthenticatedClipboardTextEvent,
): ClipboardPreview {
  const deviceLabel = event.originDeviceId.slice(0, 8);
  return {
    ...toClipboardPreview(event.item, "trusted", deviceLabel),
    id: event.itemId,
  };
}

function toHistoryItemSummary(item: HistoryItemSummaryDto): HistoryItemSummary {
  return {
    id: item.id,
    preview: item.preview,
    originDeviceId: item.originDeviceId,
    receivedAtMs: item.receivedAtMs,
    contentLength: item.contentLength,
    text: item.text,
    canCopy: item.canCopy,
  };
}

function trimPreview(text: string): string {
  if (text.length <= 180) {
    return text;
  }
  return `${text.slice(0, 90)}\n……\n${text.slice(-60)}`;
}

function formatClipboardError(error: ClipboardTextError | null): string {
  if (error === "empty") {
    return "clipboard-read-empty";
  }
  if (error && typeof error === "object" && "tooLarge" in error) {
    return `clipboard-read-too-large:${error.tooLarge.actualBytes}:${error.tooLarge.maxBytes}`;
  }
  return "clipboard-read-failed";
}
