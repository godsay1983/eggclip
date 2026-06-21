import { EGGCLIP_MDNS_SERVICE_TYPE, MdnsServiceCandidate, PocLifecycleState } from '../../models/PocModels';

export class MdnsDiscoveryService {
  private state: PocLifecycleState = PocLifecycleState.IDLE;
  private candidates: MdnsServiceCandidate[] = [];

  serviceType(): string {
    return EGGCLIP_MDNS_SERVICE_TYPE;
  }

  currentState(): PocLifecycleState {
    return this.state;
  }

  startSearch(): MdnsServiceCandidate[] {
    this.state = PocLifecycleState.RUNNING;
    return this.candidates;
  }

  stopSearch(): void {
    this.state = PocLifecycleState.IDLE;
    this.candidates = [];
  }

  mergeCandidate(candidate: MdnsServiceCandidate): MdnsServiceCandidate[] {
    const existingIndex = this.candidates.findIndex((item: MdnsServiceCandidate) => item.instanceId === candidate.instanceId);
    if (existingIndex >= 0) {
      this.candidates[existingIndex] = candidate;
    } else {
      this.candidates.push(candidate);
    }
    return this.candidates;
  }
}
