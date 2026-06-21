import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { ClipboardPreview, ShellSnapshot } from "$lib/types/shell";

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

export function createInitialShellSnapshot(): ShellSnapshot {
  return {
    connection: {
      state: "offline",
      title: "等待配对设备",
      description: "桌面端将在局域网中自动发现可信设备",
    },
    current: null,
    devices: [
      {
        id: "placeholder",
        name: "等待配对设备",
        state: "offline",
      },
    ],
    history: {
      used: 0,
      limit: 50,
    },
    syncEnabled: true,
  };
}

export async function readSystemClipboardText(): Promise<ClipboardPreview> {
  const result = await invoke<ClipboardReadResult>("read_clipboard_text");
  if (result.item) {
    return toClipboardPreview(result.item, "本机剪贴板");
  }
  throw new Error(formatClipboardError(result.error));
}

export async function writeSystemClipboardText(text: string): Promise<void> {
  await invoke("write_clipboard_text", { text });
}

export async function onLocalClipboardText(
  handler: (preview: ClipboardPreview) => void,
): Promise<() => void> {
  const unlisten = await listen<ClipboardMonitorEvent>(
    "clipboard://local-text",
    (event) => {
      handler(toClipboardPreview(event.payload.item, "本机剪贴板 · 自动监听"));
    },
  );

  return unlisten;
}

function toClipboardPreview(
  item: ClipboardTextItem,
  source: string,
): ClipboardPreview {
  return {
    id: `local-${item.digest}`,
    title: `${item.byteLen} 字节文本`,
    text: item.text,
    preview: trimPreview(item.text),
    source,
    receivedAt: new Date().toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    }),
    canCopy: true,
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
    return "剪贴板为空，或当前内容不是可同步的纯文本。";
  }
  if (error && typeof error === "object" && "tooLarge" in error) {
    return `剪贴板文本过大：${error.tooLarge.actualBytes} 字节，当前上限为 ${error.tooLarge.maxBytes} 字节。`;
  }
  return "无法读取可同步的剪贴板文本。";
}
