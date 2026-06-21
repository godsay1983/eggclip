export const EGGCLIP_MDNS_SERVICE_TYPE: string = '_eggclip._tcp.local.';
// Harmony mDNS APIs expect the DNS-SD service type without the `.local.` domain.
export const EGGCLIP_MDNS_DISCOVERY_TYPE: string = '_eggclip._tcp';
export const POC_MAX_FRAME_BYTES: number = 1024 * 1024;

export enum PocLifecycleState {
  IDLE = 'idle',
  STARTING = 'starting',
  RUNNING = 'running',
  FAILED = 'failed'
}

export enum ClipboardValidationError {
  EMPTY = 'empty',
  TOO_LARGE = 'tooLarge'
}

export interface ClipboardValidationResult {
  ok: boolean;
  byteLength: number;
  error?: ClipboardValidationError;
}

export interface ManualEndpoint {
  host: string;
  port: number;
}

export interface EndpointValidationResult {
  ok: boolean;
  normalizedUrl: string;
  reason?: string;
}

export interface MdnsServiceCandidate {
  instanceId: string;
  serviceName: string;
  host: string;
  port: number;
  protocolVersion: number;
}

export interface PocRuntimeState {
  discoveryState: PocLifecycleState;
  transportState: PocLifecycleState;
  candidateCount: number;
  lastError: string;
}
