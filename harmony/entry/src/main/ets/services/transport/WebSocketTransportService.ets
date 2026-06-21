import { EndpointValidationResult, ManualEndpoint, PocLifecycleState } from '../../models/PocModels';

export class WebSocketTransportService {
  private state: PocLifecycleState = PocLifecycleState.IDLE;

  currentState(): PocLifecycleState {
    return this.state;
  }

  validateEndpoint(endpoint: ManualEndpoint): EndpointValidationResult {
    const host = endpoint.host.trim();
    if (host.length === 0) {
      return {
        ok: false,
        normalizedUrl: '',
        reason: 'host is required'
      };
    }
    if (endpoint.port < 1 || endpoint.port > 65535) {
      return {
        ok: false,
        normalizedUrl: '',
        reason: 'port is out of range'
      };
    }
    return {
      ok: true,
      normalizedUrl: `ws://${host}:${endpoint.port}`
    };
  }

  connect(endpoint: ManualEndpoint): EndpointValidationResult {
    const result = this.validateEndpoint(endpoint);
    this.state = result.ok ? PocLifecycleState.STARTING : PocLifecycleState.FAILED;
    return result;
  }

  close(): void {
    this.state = PocLifecycleState.IDLE;
  }
}
