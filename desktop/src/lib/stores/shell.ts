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
  describePocTransport,
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
  title: string,
  description: string,
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

function updatePocDevices(title: string, description: string) {
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
    trustedDevices.some((device) => device.state === "online") ? "可信设备已连接" : "等待设备连接",
    trustedDevices.length > 0 ? `已保存 ${trustedDevices.length} 个可信设备` : "尚未完成正式配对",
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
          title: "本机同步服务已启动",
          description: describePocTransport(transport),
        },
      }));
    } catch (error) {
      pocTransportStarted = false;
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "本机同步服务启动失败",
          description: error instanceof Error ? error.message : "无法启动本机同步服务",
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
              title: "已通过加密会话同步",
              description: `已发送到 ${event.sentPeers} 个可信设备。`,
            });
            return;
          }
          if (event.status === "skippedNoAuthenticatedPeer") {
            setOutboundStatus({
              state: "waiting",
              title: "本机记录已保存",
              description: "当前没有已认证设备在线，等待可信设备连接后再同步。",
            });
            return;
          }
          if (event.status === "skippedAmbiguousSpace") {
            setOutboundStatus({
              state: "waiting",
              title: "本机记录已保存",
              description: "当前存在多个认证同步空间，待连接管理器选择目标空间。",
            });
            return;
          }
          if (event.status === "skippedByPolicy") {
            setOutboundStatus({
              state: "paused",
              title: "同步已暂停",
              description: "本机记录已保存；重新开启同步后才会发送到可信设备。",
            });
            return;
          }
          setOutboundStatus({
            state: "failed",
            title: "正式同步处理失败",
            description: "本机复制未受影响；请检查可信设备和本地密钥状态。",
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
                title: "自动接收已暂停",
                description: "已忽略可信设备发来的实时预览；重新开启自动接收后才会显示。",
              },
            }));
            return;
          }
          const deviceLabel = event.originDeviceId.slice(0, 8) || "未知设备";
          setCurrentClipboard(
            current,
            "已收到 Harmony 文本",
            `来自可信设备 ${deviceLabel}；已通过认证加密会话接收。`,
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
              title: "空间密钥已更新",
              description: `同步空间密钥已安全轮换至 v${event.keyVersion}，旧密钥绑定的历史已清理。`,
            },
          }));
        }),
        onPocClipboardText((current, peer) => {
          if (!pocReceiveEnabled) {
            snapshot.update((state) => ({
              ...state,
              connection: {
                state: "paused",
                title: "自动接收已暂停",
                description: `已忽略来自 ${peer} 的临时文本；设置开启后才会进入面板预览`,
              },
            }));
            return;
          }
          setCurrentClipboard(
            current,
            "已收到远端文本",
            `来自 ${peer}；当前实验连接尚未认证，只进入面板预览，请由用户点击复制`,
            {
              state: "idle",
              title: "远端文本已进入预览",
              description: "不会自动回传；需要使用时请点击“复制此内容”。",
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
            "远端设备已连接",
            `当前有 ${pocPeers.size} 个实验连接，仅允许用户触发收发`,
          );
          void refreshTrustedDeviceState();
        }),
        onPocPeerDisconnected((peer) => {
          pocPeers.delete(peer);
          authenticatedPeers.delete(peer);
          updatePocDevices(
            pocPeers.size > 0 ? "远端设备已连接" : "等待设备连接",
            pocPeers.size > 0
              ? `当前还有 ${pocPeers.size} 个实验连接`
              : "同步服务继续监听，可通过 mDNS 或手动 IP 连接",
          );
          void refreshTrustedDeviceState();
        }),
        onPocDiscoveryError((message) => {
          snapshot.update((state) => ({
            ...state,
            connection: {
              state: "offline",
              title: "mDNS 发布失败",
              description: `${message}；WebSocket 和手动 IP 仍可使用`,
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
          title: "同步事件监听失败",
          description: error instanceof Error ? error.message : "无法监听同步文本事件",
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
        description: describePocTransport(transport),
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
          title: "可信设备读取失败",
          description: error instanceof Error ? error.message : "无法读取可信设备",
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
        title: "可信设备已移除",
        description: `空间密钥已轮换至 v${result.keyVersion}，已通知 ${result.deliveredPeers} 个在线设备`,
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
          errorMessage: error instanceof Error ? error.message : "无法读取同步空间",
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
          errorMessage: error instanceof Error ? error.message : "无法初始化默认同步空间",
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
          title: "已创建同步空间",
          description: "空间密钥已保存到 Windows 凭据库，数据库只保存密钥引用。",
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          invitation: state.syncSpace.invitation,
          errorMessage: error instanceof Error ? error.message : "无法创建同步空间",
        },
        connection: {
          state: "authFailed",
          title: "创建同步空间失败",
          description: error instanceof Error ? error.message : "无法创建同步空间",
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
            : "空间已删除，但系统凭据库中的旧密钥引用未能清理",
        },
        connection: {
          state: "offline",
          title: "同步空间已删除",
          description: "已切换到保留的同步空间；删除的空间及其本地记录不会恢复。",
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: error instanceof Error ? error.message : "无法删除同步空间",
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
            : "已离开空间，但系统凭据库中的旧密钥引用未能清理",
        },
        connection: {
          state: "offline",
          title: "已离开同步空间",
          description: "可信连接和该空间的本地记录已移除，后续需要新邀请才能再次加入。",
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: error instanceof Error ? error.message : "无法离开同步空间",
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
          title: "已切换活动同步空间",
          description: `后续本机剪贴板会发送到“${selected.displayName}”。`,
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: error instanceof Error ? error.message : "无法切换活动同步空间",
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
          errorMessage: error instanceof Error ? error.message : "无法运行空间 HMAC 诊断",
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
          title: "已生成配对邀请",
          description: `邀请 ${invitation.expiresInSeconds / 60} 分钟内有效，确认码 ${invitation.confirmationCode}`,
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: error instanceof Error ? error.message : "无法生成配对邀请",
        },
        connection: {
          state: "authFailed",
          title: "生成配对邀请失败",
          description: error instanceof Error ? error.message : "无法生成配对邀请",
        },
      }));
    }
  },
  async copyPairingInvitation(invitationString: string) {
    snapshot.update((state) => ({
      ...state,
      syncSpace: {
        ...state.syncSpace,
        state: "copyingInvitation",
        errorMessage: null,
      },
    }));
    try {
      await copyPairingInvitation(invitationString);
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
          title: "配对邀请已复制",
          description: "邀请已通过安全复制入口写入系统剪贴板，本机历史监听会忽略这次写入。",
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: error instanceof Error ? error.message : "无法复制配对邀请",
        },
        connection: {
          state: "authFailed",
          title: "复制配对邀请失败",
          description: error instanceof Error ? error.message : "无法复制配对邀请",
        },
      }));
    }
  },
  async connectPocPeer(host: string, port: number) {
    snapshot.update((state) => ({
      ...state,
      connection: {
        state: "connecting",
        title: "正在连接远端设备",
        description: `${host.trim()}:${port}`,
      },
    }));
    try {
      const endpoint = await connectPocPeer(host, port);
      rememberPocEndpoint(endpoint);
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "connecting",
          title: "远端连接已建立",
          description: `已连接 ${endpoint.label}；等待连接事件确认`,
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "连接远端设备失败",
          description: error instanceof Error ? error.message : "无法连接目标设备",
        },
      }));
      throw error;
    }
  },
  async disconnectAllPocPeers() {
    const disconnected = await disconnectAllPocPeers();
    pocPeers.clear();
    updatePocDevices(
      "已断开远端连接",
      disconnected > 0 ? `已断开 ${disconnected} 个临时连接` : "当前没有已连接设备",
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
          "已监听到本机剪贴板",
          "本机文本变化已进入面板，并将按可信设备状态处理同步",
          {
            state: "pending",
            title: "正在处理本机记录",
            description: "正在保存本机事件，并在可信设备在线时通过加密会话同步。",
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
          title: "剪贴板监听启动失败",
          description: error instanceof Error ? error.message : "无法启动本机剪贴板监听",
        },
      }));
    }
  },
  async readLocalClipboard() {
    snapshot.update((current) => ({
      ...current,
      connection: {
        state: "connecting",
        title: "正在读取本机剪贴板",
        description: "只读取纯文本，并执行大小边界检查",
      },
    }));
    try {
      const current = await readSystemClipboardText();
      setCurrentClipboard(
        current,
        "已读取本机剪贴板",
        "当前内容已进入面板，尚未同步到其他设备",
        {
          state: "local",
          title: "本机文本已就绪",
          description: "未自动发送；点击“发送到 Harmony”后才会通过 POC 连接发送。",
          updatedAt: current.receivedAt,
        },
      );
      await captureHistoryText(current.text);
      setOutboundStatus({
        state: "local",
        title: "本机记录已处理",
        description: "可由用户点击“发送到 Harmony”进行 POC 发送。",
      });
    } catch (error) {
      setOutboundStatus({
        state: "failed",
        title: "读取或保存失败",
        description: error instanceof Error ? error.message : "无法读取或保存本机剪贴板文本。",
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "读取剪贴板失败",
          description: error instanceof Error ? error.message : "无法读取本机剪贴板",
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
          title: "读取历史数量失败",
          description: error instanceof Error ? error.message : "无法读取本机历史数量",
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
          title: "已清空本机历史",
          description:
            cleared > 0
              ? `已从本机历史中移除 ${cleared} 条记录；不会清空系统剪贴板`
              : "当前没有可清空的本机历史记录",
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "清空历史失败",
          description: error instanceof Error ? error.message : "无法清空本机历史",
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
          title: deleted ? "已删除历史记录" : "历史记录已不存在",
          description: deleted
            ? "已从本机历史中移除此记录；不会修改当前系统剪贴板"
            : "该记录可能已被清空或删除",
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "删除历史记录失败",
          description: error instanceof Error ? error.message : "无法删除本机历史记录",
        },
      }));
      throw error;
    }
  },
  async sendCurrentToHarmony(syncEnabled = true) {
    if (!syncEnabled) {
      setOutboundStatus({
        state: "paused",
        title: "同步已暂停",
        description: "当前设置关闭了自动同步，未向远端发送当前文本。",
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "paused",
          title: "同步已暂停",
          description: "当前设置关闭了自动同步，未向 Harmony 发送文本",
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
        title: "正在安全发送",
        description: "正在通过正式认证会话发送 ITEM_LIVE。",
      });
      const sentCount = await sendAuthenticatedClipboardText(text);
      setOutboundStatus({
        state: sentCount > 0 ? "sent" : "waiting",
        title: sentCount > 0 ? "已发送到远端" : "等待连接",
        description:
          sentCount > 0
            ? `已向 ${sentCount} 个认证设备发送 ITEM_LIVE。`
            : "当前没有已认证设备；完成正式连接后可重新发送。",
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: sentCount > 0 ? "online" : "offline",
          title: sentCount > 0 ? "已发送到远端设备" : "没有已连接设备",
          description:
            sentCount > 0
              ? `已向 ${sentCount} 个连接发送当前文本`
              : "请先与 Harmony 建立正式认证连接",
        },
      }));
    } catch (error) {
      setOutboundStatus({
        state: "failed",
        title: "发送失败",
        description: error instanceof Error ? error.message : "无法发送当前文本。",
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "发送到 Harmony 失败",
          description: error instanceof Error ? error.message : "无法发送当前文本",
        },
      }));
    }
  },
};

export const onlineDeviceCount = derived(snapshot, ($snapshot) =>
  countOnlineDevices($snapshot.devices),
);
