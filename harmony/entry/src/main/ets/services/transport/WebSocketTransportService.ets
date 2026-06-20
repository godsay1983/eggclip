export interface ManualEndpoint {
  host: string;
  port: number;
}

export class WebSocketTransportService {
  connect(_endpoint: ManualEndpoint): void {
  }

  close(): void {
  }
}
