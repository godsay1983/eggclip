import { derived, writable } from "svelte/store";
import {
  connectPocPeer,
  copyPairingInvitation,
  createPairingInvitation,
  createLocalSyncSpace,
  createInitialShellSnapshot,
  ensureDefaultSyncSpace,
  captureClipboardHistoryText,
  clearClipboardHistory,
  deleteLocalSyncSpace,
  deleteClipboardHistoryItem,
  disconnectAllPocPeers,
  getClipboardHistoryUsed,
  getPocTransportStatus,
  listClipboardHistoryPreview,
  listTrustedDevices,
  listLocalSyncSpaces,
  leaveMemberSyncSpace,
  loadActiveSyncSpaceId,
  loadPocRecentEndpoint,
  onAuthenticatedLocalBroadcast,
  onAuthenticatedClipboardText,
  onAuthenticatedConnection,
  onLocalClipboardText,
  onPocClipboardText,
  onPocDiagnostics,
  onPocDiscoveryError,
  onPocPeerConnected,
  onPocPeerDisconnected,
  onSpaceKeyRotated,
  readSystemClipboardText,
  removeTrustedDevice as removeTrustedDeviceApi,
  renameTrustedDevice as renameTrustedDeviceApi,
  runSpaceHmacDiagnostic as runSpaceHmacDiagnosticApi,
  sendAuthenticatedClipboardText,
  selectActiveSyncSpace as selectActiveSyncSpaceApi,
  startPocTransport,
  writeSystemClipboardText,
} from "$lib/api/shell";
import type { ClipboardPreview, DeviceSummary, OutboundSyncStatus } from "$lib/types/shell";
import type { PocRecentEndpoint } from "$lib/types/shell";
import { countOnlineDevices, mergeRuntimeDevices } from "$lib/stores/shell-state";
import { uiMessage, type UiMessageDescriptor } from "$lib/i18n";

const snapshot = writable(createInitialShellSnapshot());
let monitorStarted = false;
let pocEventsStarted = false;
let pocTransportStarted = false;
let pocReceiveEnabled = true;
let trustedDeviceRefreshTimer: ReturnType<typeof setInterval> | null = null;
const pocPeers = new Set<string>();
const authenticatedPeers = new Set<string>();
const authenticatedDeviceIds = new Set<string>();
let trustedDevices: DeviceSummary[] = [];

async function refreshHistorySummaryState() {
  const [used, items] = await Promise.all([
    getClipboardHistoryUsed(),
    listClipboardHistoryPreview(),
  ]);
  snapshot.update((state) => ({
    ...state,
    history: {
      ...state.history,
      used,
      items,
    },
  }));
}

async function captureHistoryText(text: string): Promise<boolean> {
  if (text.length === 0) {
    return false;
  }
  const captured = await captureClipboardHistoryText(text);
  if (captured) {
    await refreshHistorySummaryState();
    return true;
  }
  return false;
}

function setCurrentClipboard(
  current: ClipboardPreview,
  title: UiMessageDescriptor,
  description: UiMessageDescriptor,
  outbound?: OutboundSyncStatus,
) {
  snapshot.update((state) => ({
    ...state,
    connection: {
      state: "online",
      title,
      description,
    },
    current,
    outbound: outbound ?? state.outbound,
  }));
}

function currentTimeLabel() {
  return new Date().toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function setOutboundStatus(status: Omit<OutboundSyncStatus, "updatedAt">) {
  snapshot.update((state) => ({
    ...state,
    outbound: {
      ...status,
      updatedAt: currentTimeLabel(),
    },
  }));
}

function rememberPocEndpoint(endpoint: PocRecentEndpoint) {
  snapshot.update((state) => ({
    ...state,
    lastPocEndpoint: endpoint,
  }));
}

function updatePocDevices(title: UiMessageDescriptor, description: UiMessageDescriptor) {
  const peers = Array.from(pocPeers)
    .filter((peer) => !authenticatedPeers.has(peer))
    .sort();
  const devices = mergeRuntimeDevices(trustedDevices, peers, authenticatedPeers);
  snapshot.update((state) => ({
    ...state,
    connection: {
      state: peers.length > 0 ? "online" : "connecting",
      title,
      description,
    },
    devices,
  }));
}

async function refreshTrustedDeviceState(): Promise<void> {
  trustedDevices = (await listTrustedDevices()).map((device) =>
    authenticatedDeviceIds.has(device.id)
      ? {
          ...device,
          state: "online" as const,
          lastSeen: "当前会话在线",
          note: "认证会话在线",
        }
      : device,
  );
  updatePocDevices(
    trustedDevices.some((device) => device.state === "online")
      ? uiMessage("connection.trustedOnlineTitle")
      : uiMessage("connection.waitingTitle"),
    trustedDevices.length > 0
      ? uiMessage("connection.trustedCountDescription", { count: trustedDevices.length })
      : uiMessage("connection.noTrustedDescription"),
  );
}

export const shellSnapshot = {
  subscribe: snapshot.subscribe,
  setPocReceivePolicy(syncEnabled: boolean, autoReceiveEnabled: boolean) {
    pocReceiveEnabled = syncEnabled && autoReceiveEnabled;
  },
  async startPocTransport() {
    if (pocTransportStarted) {
      return;
    }
    pocTransportStarted = true;
    try {
      const transport = await startPocTransport();
      snapshot.update((state) => ({
        ...state,
        pocTransport: transport,
        connection: {
          state: "connecting",
          title: uiMessage("connection.serviceStartedTitle"),
          description: uiMessage("connection.serviceStartedDescription", { port: transport.port }),
        },
      }));
    } catch (error) {
      pocTransportStarted = false;
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("connection.serviceStartFailedTitle"),
          description: uiMessage("connection.serviceStartFailedDescription"),
        },
      }));
    }
  },
  async startPocEventListeners() {
    if (pocEventsStarted) {
      return;
    }
    pocEventsStarted = true;
    try {
      await Promise.all([
        onAuthenticatedLocalBroadcast((event) => {
          void refreshHistorySummaryState();
          if (event.status === "sent") {
            setOutboundStatus({
              state: "sent",
              title: uiMessage("sync.sentTitle"),
              description: uiMessage("sync.sentDescription", { count: event.sentPeers }),
            });
            return;
          }
          if (event.status === "skippedNoAuthenticatedPeer") {
            setOutboundStatus({
              state: "waiting",
              title: uiMessage("sync.localSavedTitle"),
              description: uiMessage("sync.noPeerDescription"),
            });
            return;
          }
          if (event.status === "skippedAmbiguousSpace") {
            setOutboundStatus({
              state: "waiting",
              title: uiMessage("sync.localSavedTitle"),
              description: uiMessage("sync.ambiguousSpaceDescription"),
            });
            return;
          }
          if (event.status === "skippedByPolicy") {
            setOutboundStatus({
              state: "paused",
              title: uiMessage("sync.pausedTitle"),
              description: uiMessage("sync.pausedDescription"),
            });
            return;
          }
          setOutboundStatus({
            state: "failed",
            title: uiMessage("sync.failedTitle"),
            description: uiMessage("sync.failedDescription"),
          });
        }),
        onAuthenticatedConnection((event) => {
          if (event.state === "online") {
            authenticatedPeers.add(event.peer);
            authenticatedDeviceIds.add(event.deviceId);
          } else {
            authenticatedPeers.delete(event.peer);
            authenticatedDeviceIds.delete(event.deviceId);
          }
          void refreshTrustedDeviceState();
        }),
        onAuthenticatedClipboardText((current, event) => {
          if (!pocReceiveEnabled) {
            snapshot.update((state) => ({
              ...state,
              connection: {
                state: "paused",
                title: uiMessage("receive.pausedTitle"),
                description: uiMessage("receive.trustedPausedDescription"),
              },
            }));
            return;
          }
          const deviceLabel = event.originDeviceId.slice(0, 8) || "未知设备";
          setCurrentClipboard(
            current,
            uiMessage("receive.trustedTitle"),
            uiMessage("receive.trustedDescription", { deviceLabel }),
          );
          void refreshHistorySummaryState();
        }),
        onSpaceKeyRotated((event) => {
          void Promise.all([
            shellSnapshot.refreshSyncSpaces(),
            refreshHistorySummaryState(),
          ]);
          snapshot.update((state) => ({
            ...state,
            connection: {
              state: "online",
              title: uiMessage("space.keyUpdatedTitle"),
              description: uiMessage("space.keyUpdatedDescription", { version: event.keyVersion }),
            },
          }));
        }),
        onPocClipboardText((current, peer) => {
          if (!pocReceiveEnabled) {
            snapshot.update((state) => ({
              ...state,
              connection: {
                state: "paused",
                title: uiMessage("receive.pausedTitle"),
                description: uiMessage("receive.pocPausedDescription", { peer }),
              },
            }));
            return;
          }
          setCurrentClipboard(
            current,
            uiMessage("receive.pocTitle"),
            uiMessage("receive.pocDescription", { peer }),
            {
              state: "idle",
              title: uiMessage("receive.previewTitle"),
              description: uiMessage("receive.previewDescription"),
              updatedAt: current.receivedAt,
            },
          );
        }),
        onPocDiagnostics((pocDiagnostics) => {
          snapshot.update((state) => ({
            ...state,
            pocDiagnostics,
          }));
        }),
        onPocPeerConnected((peer) => {
          pocPeers.add(peer);
          updatePocDevices(
            uiMessage("connection.peerConnectedTitle"),
            uiMessage("connection.peerConnectedDescription", { count: pocPeers.size }),
          );
          void refreshTrustedDeviceState();
        }),
        onPocPeerDisconnected((peer) => {
          pocPeers.delete(peer);
          authenticatedPeers.delete(peer);
          updatePocDevices(
            pocPeers.size > 0
              ? uiMessage("connection.peerConnectedTitle")
              : uiMessage("connection.waitingTitle"),
            pocPeers.size > 0
              ? uiMessage("connection.peerRemainingDescription", { count: pocPeers.size })
              : uiMessage("connection.serviceListeningDescription"),
          );
          void refreshTrustedDeviceState();
        }),
        onPocDiscoveryError((message) => {
          snapshot.update((state) => ({
            ...state,
            connection: {
              state: "offline",
              title: uiMessage("discovery.publishFailedTitle"),
              description: uiMessage("discovery.publishFailedDescription"),
            },
          }));
        }),
      ]);
      if (trustedDeviceRefreshTimer === null) {
        trustedDeviceRefreshTimer = setInterval(() => {
          void refreshTrustedDeviceState();
        }, 1500);
      }
    } catch (error) {
      pocEventsStarted = false;
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("connection.eventsFailedTitle"),
          description: uiMessage("connection.eventsFailedDescription"),
        },
      }));
    }
  },
  async refreshPocTransportStatus() {
    const transport = await getPocTransportStatus();
    snapshot.update((state) => ({
      ...state,
      pocTransport: transport,
      connection: {
        ...state.connection,
        description: transport.state === "running"
          ? uiMessage("connection.serviceStartedDescription", { port: transport.port })
          : uiMessage("connection.serviceStartFailedDescription"),
      },
    }));
  },
  async refreshTrustedDevices() {
    try {
      await refreshTrustedDeviceState();
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("connection.deviceReadFailedTitle"),
          description: uiMessage("connection.deviceReadFailedDescription"),
        },
      }));
    }
  },
  async renameTrustedDevice(deviceId: string, displayName: string) {
    await renameTrustedDeviceApi(deviceId, displayName);
    await refreshTrustedDeviceState();
  },
  async removeTrustedDevice(deviceId: string) {
    const result = await removeTrustedDeviceApi(deviceId);
    await Promise.all([
      refreshTrustedDeviceState(),
      this.refreshSyncSpaces(),
      refreshHistorySummaryState(),
    ]);
    snapshot.update((state) => ({
      ...state,
      connection: {
        state: result.deliveredPeers > 0 ? "online" : "offline",
        title: uiMessage("device.removedTitle"),
        description: uiMessage("device.removedDescription", {
          version: result.keyVersion,
          count: result.deliveredPeers,
        }),
      },
    }));
    return result;
  },
  async loadRecentPocEndpoint() {
    try {
      const endpoint = await loadPocRecentEndpoint();
      snapshot.update((state) => ({
        ...state,
        lastPocEndpoint: endpoint,
      }));
    } catch (_) {
      snapshot.update((state) => ({
        ...state,
        lastPocEndpoint: null,
      }));
    }
  },
  async refreshSyncSpaces() {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "loading",
        errorMessage: null,
      },
    }));
    try {
      const [spaces, activeSpaceId] = await Promise.all([
        listLocalSyncSpaces(),
        loadActiveSyncSpaceId(),
      ]);
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          state: spaces.length > 0 ? "ready" : "idle",
          spaces,
          activeSpaceId,
          hmacDiagnostic: activeSpaceId === state.syncSpace.activeSpaceId
            ? state.syncSpace.hmacDiagnostic
            : null,
          invitation: state.syncSpace.invitation,
          invitationCopiedAt: state.syncSpace.invitationCopiedAt,
          errorMessage: null,
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          invitation: state.syncSpace.invitation,
          errorMessage: uiMessage("space.loadFailed"),
        },
      }));
    }
  },
  async ensureDefaultSyncSpace() {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: state.syncSpace.spaces.length > 0 ? "loading" : "creating",
        errorMessage: null,
      },
    }));
    try {
      const space = await ensureDefaultSyncSpace();
      const activeSpaceId = await loadActiveSyncSpaceId();
      snapshot.update((state) => {
        const spaces = [
          space,
          ...state.syncSpace.spaces.filter((candidate) => candidate.id !== space.id),
        ];
        return {
          ...state,
          syncSpace: {
            state: "ready",
            spaces,
            activeSpaceId,
            hmacDiagnostic: state.syncSpace.hmacDiagnostic,
            invitation: state.syncSpace.invitation,
            invitationCopiedAt: state.syncSpace.invitationCopiedAt,
            errorMessage: null,
          },
        };
      });
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          invitation: state.syncSpace.invitation,
          errorMessage: uiMessage("space.initializeFailed"),
        },
      }));
    }
  },
  async createDefaultSyncSpace() {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "creating",
        errorMessage: null,
      },
    }));
    try {
      const existingSpaces = await listLocalSyncSpaces();
      const usedNames = new Set(existingSpaces.map((space) => space.displayName));
      let suffix = existingSpaces.length + 1;
      let displayName = `同步空间 ${suffix}`;
      while (usedNames.has(displayName)) {
        suffix += 1;
        displayName = `同步空间 ${suffix}`;
      }
      const space = await createLocalSyncSpace(displayName);
      const activeSpaceId = await loadActiveSyncSpaceId();
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          state: "ready",
          spaces: [space, ...state.syncSpace.spaces],
          activeSpaceId,
          hmacDiagnostic: null,
          invitation: null,
          invitationCopiedAt: null,
          errorMessage: null,
        },
        connection: {
          state: "online",
          title: uiMessage("space.createdTitle"),
          description: uiMessage("space.createdDescription"),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          invitation: state.syncSpace.invitation,
          errorMessage: uiMessage("space.createFailedDescription"),
        },
        connection: {
          state: "authFailed",
          title: uiMessage("space.createFailedTitle"),
          description: uiMessage("space.createFailedDescription"),
        },
      }));
    }
  },
  async deleteSyncSpace(spaceId: string) {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "loading",
        errorMessage: null,
      },
    }));
    try {
      const result = await deleteLocalSyncSpace(spaceId);
      const spaces = await listLocalSyncSpaces();
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          state: "ready",
          spaces,
          activeSpaceId: result.activeSpaceId,
          hmacDiagnostic: null,
          invitation: null,
          invitationCopiedAt: null,
          errorMessage: result.credentialDeleted
            ? null
            : uiMessage("space.credentialCleanupFailed"),
        },
        connection: {
          state: "offline",
          title: uiMessage("space.deletedTitle"),
          description: uiMessage("space.deletedDescription"),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: uiMessage("space.deleteFailed"),
        },
      }));
      throw error;
    }
  },
  async leaveSyncSpace(spaceId: string) {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "loading",
        errorMessage: null,
      },
    }));
    try {
      const result = await leaveMemberSyncSpace(spaceId);
      const spaces = await listLocalSyncSpaces();
      await Promise.all([refreshTrustedDeviceState(), refreshHistorySummaryState()]);
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          state: "ready",
          spaces,
          activeSpaceId: result.activeSpaceId,
          hmacDiagnostic: null,
          invitation: null,
          invitationCopiedAt: null,
          errorMessage: result.credentialDeleted
            ? null
            : uiMessage("space.leaveCredentialCleanupFailed"),
        },
        connection: {
          state: "offline",
          title: uiMessage("space.leftTitle"),
          description: uiMessage("space.leftDescription"),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: uiMessage("space.leaveFailed"),
        },
      }));
      throw error;
    }
  },
  async selectActiveSyncSpace(spaceId: string) {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "loading",
        errorMessage: null,
      },
    }));
    try {
      const selected = await selectActiveSyncSpaceApi(spaceId);
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "ready",
          activeSpaceId: selected.id,
          hmacDiagnostic: null,
          errorMessage: null,
        },
        connection: {
          state: "online",
          title: uiMessage("space.selectedTitle"),
          description: uiMessage("space.selectedDescription", { spaceName: selected.displayName }),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: uiMessage("space.selectFailed"),
        },
      }));
    }
  },
  async runSpaceHmacDiagnostic() {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "loading",
        hmacDiagnostic: null,
        errorMessage: null,
      },
    }));
    try {
      const diagnostic = await runSpaceHmacDiagnosticApi();
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "ready",
          activeSpaceId: diagnostic.spaceId,
          hmacDiagnostic: diagnostic,
          errorMessage: null,
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          hmacDiagnostic: null,
          errorMessage: uiMessage("space.diagnosticFailed"),
        },
      }));
    }
  },
  async createPairingInvitation(spaceId: string) {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "inviting",
        invitationCopiedAt: null,
        errorMessage: null,
      },
    }));
    try {
      const invitation = await createPairingInvitation(spaceId);
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "ready",
          invitation,
          invitationCopiedAt: null,
          errorMessage: null,
        },
        connection: {
          state: "connecting",
          title: uiMessage("pairing.invitationCreatedTitle"),
          description: uiMessage("pairing.invitationCreatedDescription", {
            minutes: invitation.expiresInSeconds / 60,
          }),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: uiMessage("pairing.invitationCreateFailedDescription"),
        },
        connection: {
          state: "authFailed",
          title: uiMessage("pairing.invitationCreateFailedTitle"),
          description: uiMessage("pairing.invitationCreateFailedDescription"),
        },
      }));
    }
  },
  async copyPairingInvitation(invitationId: string) {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "copyingInvitation",
        errorMessage: null,
      },
    }));
    try {
      await copyPairingInvitation(invitationId);
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "ready",
          invitationCopiedAt: currentTimeLabel(),
          errorMessage: null,
        },
        connection: {
          state: "connecting",
          title: uiMessage("pairing.invitationCopiedTitle"),
          description: uiMessage("pairing.invitationCopiedDescription"),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: uiMessage("pairing.invitationCopyFailedDescription"),
        },
        connection: {
          state: "authFailed",
          title: uiMessage("pairing.invitationCopyFailedTitle"),
          description: uiMessage("pairing.invitationCopyFailedDescription"),
        },
      }));
    }
  },
  async connectPocPeer(host: string, port: number) {
    snapshot.update((state) => ({
      ...state,
      connection: {
        state: "connecting",
        title: uiMessage("connection.connectingTitle"),
        description: uiMessage("connection.endpointDescription", {
          endpoint: `${host.trim()}:${port}`,
        }),
      },
    }));
    try {
      const endpoint = await connectPocPeer(host, port);
      rememberPocEndpoint(endpoint);
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "connecting",
          title: uiMessage("connection.establishedTitle"),
          description: uiMessage("connection.establishedDescription", { endpoint: endpoint.label }),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("connection.connectFailedTitle"),
          description: uiMessage("connection.connectFailedDescription"),
        },
      }));
      throw error;
    }
  },
  async disconnectAllPocPeers() {
    const disconnected = await disconnectAllPocPeers();
    pocPeers.clear();
    updatePocDevices(
      uiMessage("connection.disconnectedTitle"),
      uiMessage("connection.disconnectedDescription", { count: disconnected }),
    );
  },
  async startClipboardMonitor() {
    if (monitorStarted) {
      return;
    }
    monitorStarted = true;
    try {
      await onLocalClipboardText((current) => {
        setCurrentClipboard(
          current,
          uiMessage("clipboard.monitoringTitle"),
          uiMessage("clipboard.monitoringDescription"),
          {
            state: "pending",
            title: uiMessage("sync.sendingTitle"),
            description: uiMessage("sync.sendingDescription"),
            updatedAt: current.receivedAt,
          },
        );
      });
    } catch (error) {
      monitorStarted = false;
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("clipboard.monitorFailedTitle"),
          description: uiMessage("clipboard.monitorFailedDescription"),
        },
      }));
    }
  },
  async readLocalClipboard() {
    snapshot.update((current) => ({
      ...current,
      connection: {
        state: "connecting",
        title: uiMessage("clipboard.readingTitle"),
        description: uiMessage("clipboard.readingDescription"),
      },
    }));
    try {
      const current = await readSystemClipboardText();
      setCurrentClipboard(
        current,
        uiMessage("clipboard.readTitle"),
        uiMessage("clipboard.readDescription"),
        {
          state: "local",
          title: uiMessage("clipboard.localReadyTitle"),
          description: uiMessage("clipboard.localReadyDescription"),
          updatedAt: current.receivedAt,
        },
      );
      await captureHistoryText(current.text);
      setOutboundStatus({
        state: "local",
        title: uiMessage("clipboard.localProcessedTitle"),
        description: uiMessage("clipboard.localProcessedDescription"),
      });
    } catch (error) {
      setOutboundStatus({
        state: "failed",
        title: uiMessage("clipboard.readFailedTitle"),
        description: uiMessage("clipboard.readFailedDescription"),
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("clipboard.readFailedTitle"),
          description: uiMessage("clipboard.readFailedDescription"),
        },
      }));
    }
  },
  async copyCurrentToClipboard() {
    let text = "";
    const unsubscribe = snapshot.subscribe((state) => {
      text = state.current?.text ?? "";
    });
    unsubscribe();
    if (text.length === 0) {
      return;
    }
    await writeSystemClipboardText(text);
  },
  async copyHistoryItem(itemId: string) {
    let text: string | null = null;
    const unsubscribe = snapshot.subscribe((state) => {
      text = state.history.items.find((item) => item.id === itemId)?.text ?? null;
    });
    unsubscribe();
    if (!text) {
      return false;
    }
    await writeSystemClipboardText(text);
    return true;
  },
  async refreshHistorySummary() {
    try {
      await refreshHistorySummaryState();
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("history.readFailedTitle"),
          description: uiMessage("history.readFailedDescription"),
        },
      }));
    }
  },
  async clearHistory() {
    try {
      const cleared = await clearClipboardHistory();
      snapshot.update((state) => ({
        ...state,
        history: {
          ...state.history,
          used: 0,
          items: [],
        },
        connection: {
          state: "online",
          title: uiMessage("history.clearedTitle"),
          description:
            cleared > 0
              ? uiMessage("history.clearedDescription", { count: cleared })
              : uiMessage("history.emptyDescription"),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("history.clearFailedTitle"),
          description: uiMessage("history.clearFailedDescription"),
        },
      }));
      throw error;
    }
  },
  async deleteHistoryItem(itemId: string) {
    try {
      const deleted = await deleteClipboardHistoryItem(itemId);
      await this.refreshHistorySummary();
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "online",
          title: deleted
            ? uiMessage("history.deletedTitle")
            : uiMessage("history.missingTitle"),
          description: deleted
            ? uiMessage("history.deletedDescription")
            : uiMessage("history.missingDescription"),
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("history.deleteFailedTitle"),
          description: uiMessage("history.deleteFailedDescription"),
        },
      }));
      throw error;
    }
  },
  async sendCurrentToHarmony(syncEnabled = true) {
    if (!syncEnabled) {
      setOutboundStatus({
        state: "paused",
        title: uiMessage("sync.pausedTitle"),
        description: uiMessage("sync.pausedDescription"),
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "paused",
          title: uiMessage("sync.pausedTitle"),
          description: uiMessage("sync.pausedDescription"),
        },
      }));
      return;
    }

    let text = "";
    const unsubscribe = snapshot.subscribe((state) => {
      text = state.current?.text ?? "";
    });
    unsubscribe();
    if (text.length === 0) {
      return;
    }

    try {
      setOutboundStatus({
        state: "pending",
        title: uiMessage("sync.sendingTitle"),
        description: uiMessage("sync.sendingDescription"),
      });
      const sentCount = await sendAuthenticatedClipboardText(text);
      setOutboundStatus({
        state: sentCount > 0 ? "sent" : "waiting",
        title: sentCount > 0
          ? uiMessage("sync.remoteSentTitle")
          : uiMessage("sync.waitingTitle"),
        description:
          sentCount > 0
            ? uiMessage("sync.remoteSentDescription", { count: sentCount })
            : uiMessage("sync.waitingDescription"),
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: sentCount > 0 ? "online" : "offline",
          title: sentCount > 0
            ? uiMessage("sync.remoteSentTitle")
            : uiMessage("sync.noConnectionTitle"),
          description:
            sentCount > 0
              ? uiMessage("sync.remoteSentDescription", { count: sentCount })
              : uiMessage("sync.noConnectionDescription"),
        },
      }));
    } catch (error) {
      setOutboundStatus({
        state: "failed",
        title: uiMessage("sync.failedTitle"),
        description: uiMessage("sync.failedDescription"),
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: uiMessage("sync.failedTitle"),
          description: uiMessage("sync.failedDescription"),
        },
      }));
    }
  },
};

export const onlineDeviceCount = derived(snapshot, ($snapshot) =>
  countOnlineDevices($snapshot.devices),
);
