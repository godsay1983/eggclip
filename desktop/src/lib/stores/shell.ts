import { derived, writable } from "svelte/store";
import {
  createInitialShellSnapshot,
  readSystemClipboardText,
  writeSystemClipboardText,
} from "$lib/api/shell";

const snapshot = writable(createInitialShellSnapshot());

export const shellSnapshot = {
  subscribe: snapshot.subscribe,
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
      snapshot.update((state) => ({
        ...state,
        connection: {
          state: "online",
          title: "已读取本机剪贴板",
          description: "当前内容只显示在本机面板，尚未同步到其他设备",
        },
        current,
      }));
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
