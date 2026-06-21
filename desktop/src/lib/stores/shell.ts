import { derived, writable } from "svelte/store";
import {
  createInitialShellSnapshot,
  getPocTransportStatus,
  onLocalClipboardText,
  onPocClipboardText,
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
          title: "WebSocket POC 服务已启动",
          description,
        },
      }));
    } catch (error) {
      pocTransportStarted = false;
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "WebSocket POC 服务启动失败",
          description: error instanceof Error ? error.message : "无法启动本地 POC 服务",
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
      await onPocClipboardText((current, peer) => {
        setCurrentClipboard(
          current,
          "已收到 Harmony POC 文本",
          `来自 ${peer}；POC 尚未认证，只进入面板预览，请由用户点击复制`,
        );
      });
    } catch (error) {
      pocEventsStarted = false;
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "WebSocket POC 事件监听失败",
          description: error instanceof Error ? error.message : "无法监听 POC 文本事件",
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
          "这是 D1 POC：本机文本变化只更新面板，需由用户点击发送给 Harmony POC",
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
        description: "这是 D1 POC：先验证纯文本读取和大小边界",
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
          title: sentCount > 0 ? "已发送到 Harmony POC" : "没有已连接的 Harmony POC",
          description:
            sentCount > 0
              ? `已向 ${sentCount} 个 POC 连接发送当前文本`
              : "请先在 Harmony 端手动连接桌面 POC 服务",
        },
      }));
    } catch (error) {
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "authFailed",
          title: "发送到 Harmony POC 失败",
          description: error instanceof Error ? error.message : "无法发送当前文本",
        },
      }));
    }
  },
};

export const onlineDeviceCount = derived(snapshot, ($snapshot) =>
  $snapshot.devices.filter((device) => device.state === "online").length,
);
