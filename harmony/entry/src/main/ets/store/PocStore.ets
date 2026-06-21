import { PocLifecycleState, PocRuntimeState } from '../models/PocModels';

export function createInitialPocRuntimeState(): PocRuntimeState {
  return {
    discoveryState: PocLifecycleState.IDLE,
    transportState: PocLifecycleState.IDLE,
    candidateCount: 0,
    lastError: ''
  };
}
