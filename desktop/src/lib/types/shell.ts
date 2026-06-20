export type ConnectionState =
  | "offline"
  | "connecting"
  | "online"
  | "authFailed"
  | "paused";

export interface DeviceSummary {
  id: string;
  name: string;
  state: ConnectionState;
}

export interface ClipboardPreview {
  id: string;
  title: string;
  preview: string;
  source: string;
  receivedAt: string;
  canCopy: boolean;
}

export interface HistorySummary {
  used: number;
  limit: number;
}

export interface ShellSnapshot {
  connection: {
    state: ConnectionState;
    title: string;
    description: string;
  };
  current: ClipboardPreview | null;
  devices: DeviceSummary[];
  history: HistorySummary;
  syncEnabled: boolean;
}
