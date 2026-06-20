export enum ConnectionState {
  OFFLINE = 'offline',
  CONNECTING = 'connecting',
  ONLINE = 'online',
  AUTH_FAILED = 'authFailed',
  PAUSED = 'paused'
}

export interface ConnectionSummary {
  state: ConnectionState;
  title: string;
  description: string;
}

export interface ClipboardPreview {
  id: string;
  title: string;
  preview: string;
  source: string;
  receivedAt: string;
  canCopy: boolean;
}

export interface DeviceSummary {
  id: string;
  name: string;
  state: ConnectionState;
}

export interface HistorySummary {
  used: number;
  limit: number;
}

export interface HomeShellState {
  connection: ConnectionSummary;
  latest: ClipboardPreview | null;
  devices: DeviceSummary[];
  history: HistorySummary;
  syncEnabled: boolean;
}
