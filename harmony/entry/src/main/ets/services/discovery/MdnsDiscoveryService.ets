export interface MdnsServiceCandidate {
  instanceId: string;
  host: string;
  port: number;
  protocolVersion: number;
}

export class MdnsDiscoveryService {
  startSearch(): MdnsServiceCandidate[] {
    return [];
  }

  stopSearch(): void {
  }
}
