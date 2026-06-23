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
  text: string;
  preview: string;
  source: string;
  receivedAt: string;
  canCopy: boolean;
}

export interface HistorySummary {
  used: number;
  limit: number;
}

export type PocRejectionReason =
  | "frameTooLarge"
  | "invalidMessage"
  | "emptyText"
  | "textTooLarge"
  | "binaryUnsupported";

export interface PocDiagnostics {
  receivedFrames: number;
  acceptedItems: number;
  rejectedFrames: number;
  lastRejection: PocRejectionReason | null;
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
  pocDiagnostics: PocDiagnostics;
  syncEnabled: boolean;
}
