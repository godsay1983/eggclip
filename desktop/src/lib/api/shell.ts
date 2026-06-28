import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type {
  ClipboardPreview,
  HistoryItemSummary,
  PocDiagnostics,
  PocTransportSummary,
  ShellSnapshot,
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
  connectedPeers: number;
  diagnostics: PocDiagnostics;
  lastError: string | null;
}

interface PocNetworkAddress {
  interfaceName: string;
  address: string;
  isTunnel: boolean;
}

interface PocPeerEvent {
  peer: string;
}

interface HistoryItemSummaryDto {
  id: string;
  title: string;
  preview: string;
  source: string;
  receivedAtMs: number;
  contentLength: number;
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
      connectedPeers: 0,
      lastError: null,
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

export async function connectPocPeer(host: string, port: number): Promise<string> {
  return invoke<string>("connect_poc_peer", { host, port });
}

export async function disconnectAllPocPeers(): Promise<number> {
  return invoke<number>("disconnect_all_poc_peers");
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
      handler(toClipboardPreview(event.payload.item, "本机剪贴板 · 自动监听"));
    },
  );

  return unlisten;
}

export async function onPocClipboardText(
  handler: (preview: ClipboardPreview, peer: string) => void,
): Promise<() => void> {
  const unlisten = await listen<PocClipboardTextEvent>(
    "transport://poc-clipboard-text",
    (event) => {
      handler(
        toClipboardPreview(event.payload.item, `远端 POC · ${event.payload.peer}`),
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

export function describePocTransport(status: PocTransportSummary): string {
  if (status.state === "running") {
    const discovery = status.discoveryPublished
      ? "mDNS POC 服务已发布"
      : "mDNS 发布失败，可继续使用手动 IP";
    const addresses = formatPocNetworkAddresses(status.networkAddresses);
    const peers = status.connectedPeers > 0 ? `；已连接 ${status.connectedPeers} 个 POC` : "";
    return `WebSocket POC 端口 ${status.port}；${discovery}；${addresses}${peers}`;
  }
  if (status.state === "failed") {
    return status.lastError ?? "WebSocket POC 服务启动失败";
  }
  return "WebSocket POC 尚未启动";
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
    connectedPeers: status.connectedPeers,
    lastError: status.lastError,
  };
}

function formatPocNetworkAddresses(addresses: PocNetworkAddress[]): string {
  if (addresses.length === 0) {
    return "未找到可用 IPv4，请检查网络适配器";
  }
  const visible = addresses.slice(0, 5).map((item) => {
    const tunnel = item.isTunnel ? "，隧道" : "";
    return `${item.interfaceName} ${item.address}${tunnel}`;
  });
  const remaining = addresses.length - visible.length;
  return `候选地址：${visible.join("；")}${remaining > 0 ? `；另有 ${remaining} 个` : ""}`;
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

function toHistoryItemSummary(item: HistoryItemSummaryDto): HistoryItemSummary {
  return {
    id: item.id,
    title: item.title,
    preview: item.preview,
    source: item.source,
    receivedAt: new Date(item.receivedAtMs).toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    }),
    contentLength: item.contentLength,
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
