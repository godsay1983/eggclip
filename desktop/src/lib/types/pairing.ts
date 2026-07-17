export interface PairingJoinAddressSummary {
  candidateId: string;
  displayAddress: string;
}

export interface PairingJoinAttemptSummary {
  attemptId: string;
  issuerDeviceName: string;
  issuerShortFingerprint: string;
  spaceShortId: string;
  expiresAtMs: number;
  expiresInSeconds: number;
  confirmationCode: string;
  addresses: PairingJoinAddressSummary[];
}
