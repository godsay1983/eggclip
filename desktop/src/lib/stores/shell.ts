import { derived, writable } from "svelte/store";
import {
  connectPocPeer,
  createLocalSyncSpace,
  createInitialShellSnapshot,
  captureClipboardHistoryText,
  clearClipboardHistory,
  deleteClipboardHistoryItem,
  describePocTransport,
  disconnectAllPocPeers,
  getClipboardHistoryUsed,
  getPocTransportStatus,
  listClipboardHistoryPreview,
  listLocalSyncSpaces,
  loadPocRecentEndpoint,
  onLocalClipboardText,
  onPocClipboardText,
  onPocDiagnostics,
  onPocDiscoveryError,
  onPocPeerConnected,
  onPocPeerDisconnected,
  readSystemClipboardText,
  sendPocClipboardText,
  startPocTransport,
  writeSystemClipboardText,
} from "$lib/api/shell";
import type { ClipboardPreview, OutboundSyncStatus } from "$lib/types/shell";
import type { PocRecentEndpoint } from "$lib/types/shell";

const snapshot = writable(createInitialShellSnapshot());
let monitorStarted = false;
let pocEventsStarted = false;
let pocTransportStarted = false;
let pocReceiveEnabled = true;
const pocPeers = new Set<string>();

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
  const peers = Array.from(pocPeers).sort();
  snapshot.update((state) => ({
    ...state,
    connection: {
      state: peers.length > 0 ? "online" : "connecting",
      title,
      description,
    },
    devices:
      peers.length > 0
        ? peers.map((peer) => ({
            id: `poc-${peer}`,
            name: "远端 POC 连接",
            state: "online" as const,
            trustKind: "poc" as const,
            shortFingerprint: "未配对",
            lastSeen: "当前会话在线",
            endpoint: peer,
            note: "实验连接尚未完成设备身份认证，仅用于手动收发验证。",
          }))
        : [
            {
              id: "placeholder",
              name: "等待可信设备",
              state: "offline" as const,
              trustKind: "placeholder" as const,
              shortFingerprint: "等待配对",
              lastSeen: "暂无",
              note: "正式配对完成后，这里会显示设备名称、公钥短指纹和最后在线时间。",
            },
          ],
  }));
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
        }),
        onPocPeerDisconnected((peer) => {
          pocPeers.delete(peer);
          updatePocDevices(
            pocPeers.size > 0 ? "远端设备已连接" : "等待设备连接",
            pocPeers.size > 0
              ? `当前还有 ${pocPeers.size} 个实验连接`
              : "同步服务继续监听，可通过 mDNS 或手动 IP 连接",
          );
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
      const spaces = await listLocalSyncSpaces();
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          state: spaces.length > 0 ? "ready" : "idle",
          spaces,
          errorMessage: null,
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          ...state.syncSpace,
          state: "error",
          errorMessage: error instanceof Error ? error.message : "无法读取同步空间",
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
      const space = await createLocalSyncSpace("默认空间");
      snapshot.update((state) => ({
        ...state,
        syncSpace: {
          state: "ready",
          spaces: [space, ...state.syncSpace.spaces],
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
          "本机文本变化已进入面板，需由用户点击发送到 Harmony",
          {
            state: "local",
            title: "本机文本已就绪",
            description: "未自动发送；点击“发送到 Harmony”后才会通过 POC 连接发送。",
            updatedAt: current.receivedAt,
          },
        );
        void captureHistoryText(current.text)
          .then(() => {
            setOutboundStatus({
              state: "local",
              title: "本机记录已处理",
              description: "可由用户点击“发送到 Harmony”进行 POC 发送。",
            });
          })
          .catch((error) => {
            setOutboundStatus({
              state: "failed",
              title: "保存本机记录失败",
              description: "未确认本机记录处理成功，请检查本机数据库状态。",
            });
            snapshot.update((state) => ({
              ...state,
              connection: {
                state: "authFailed",
                title: "保存本机历史失败",
                description: error instanceof Error ? error.message : "无法保存本机剪贴板历史",
              },
            }));
          });
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
  async sendCurrentToPocPeer(syncEnabled = true) {
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
        title: "正在发送",
        description: "正在通过当前 POC WebSocket 连接发送文本。",
      });
      const sentCount = await sendPocClipboardText(text);
      setOutboundStatus({
        state: sentCount > 0 ? "sent" : "waiting",
        title: sentCount > 0 ? "已发送到远端" : "等待连接",
        description:
          sentCount > 0
            ? `已向 ${sentCount} 个 POC 连接发送；正式协议接入后会使用 ITEM_LIVE。`
            : "当前没有已连接设备；可连接后重新发送当前面板文本。",
      });
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: sentCount > 0 ? "online" : "offline",
          title: sentCount > 0 ? "已发送到远端设备" : "没有已连接设备",
          description:
            sentCount > 0
              ? `已向 ${sentCount} 个连接发送当前文本`
              : "请先在 Harmony 端或另一桌面实例建立连接",
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
  $snapshot.devices.filter((device) => device.state === "online").length,
);
