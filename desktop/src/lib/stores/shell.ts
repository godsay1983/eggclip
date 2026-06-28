import { derived, writable } from "svelte/store";
import {
  connectPocPeer,
  createInitialShellSnapshot,
  clearClipboardHistory,
  disconnectAllPocPeers,
  getClipboardHistoryUsed,
  getPocTransportStatus,
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
import type { ClipboardPreview } from "$lib/types/shell";

const snapshot = writable(createInitialShellSnapshot());
let monitorStarted = false;
let pocEventsStarted = false;
let pocTransportStarted = false;
const pocPeers = new Set<string>();

function setCurrentClipboard(
  current: ClipboardPreview,
  title: string,
  description: string,
) {
  snapshot.update((state) => ({
    ...state,
    connection: {
      state: "online",
      title,
      description,
    },
    current,
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
            name: peer,
            state: "online" as const,
          }))
        : [
            {
              id: "placeholder",
              name: "等待可信设备",
              state: "offline" as const,
            },
          ],
  }));
}

export const shellSnapshot = {
  subscribe: snapshot.subscribe,
  async startPocTransport() {
    if (pocTransportStarted) {
      return;
    }
    pocTransportStarted = true;
    try {
      const description = await startPocTransport();
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "connecting",
          title: "本机同步服务已启动",
          description,
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
          setCurrentClipboard(
            current,
            "已收到远端文本",
            `来自 ${peer}；当前实验连接尚未认证，只进入面板预览，请由用户点击复制`,
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
    const description = await getPocTransportStatus();
    snapshot.update((state) => ({
      ...state,
      connection: {
        ...state.connection,
        description,
      },
    }));
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
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "connecting",
          title: "远端连接已建立",
          description: `已连接 ${endpoint}；等待连接事件确认`,
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
          "本机文本变化只更新面板，需由用户点击发送到 Harmony",
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
        "当前内容只显示在本机面板，尚未同步到其他设备",
      );
    } catch (error) {
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
      const used = await getClipboardHistoryUsed();
      snapshot.update((state) => ({
        ...state,
        history: {
          ...state.history,
          used,
        },
      }));
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
  async sendCurrentToPocPeer() {
    let text = "";
    const unsubscribe = snapshot.subscribe((state) => {
      text = state.current?.text ?? "";
    });
    unsubscribe();
    if (text.length === 0) {
      return;
    }

    try {
      const sentCount = await sendPocClipboardText(text);
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
