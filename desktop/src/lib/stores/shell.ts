import { derived, writable } from "svelte/store";
import {
  createInitialShellSnapshot,
  getPocTransportStatus,
  onLocalClipboardText,
  onPocClipboardText,
  readSystemClipboardText,
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
          `来自 ${peer}；当前只进入面板预览，不自动写入系统剪贴板`,
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
          "这是 D1 POC：本机文本变化会自动显示在面板中，尚未同步到其他设备",
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
};

export const onlineDeviceCount = derived(snapshot, ($snapshot) =>
  $snapshot.devices.filter((device) => device.state === "online").length,
);
