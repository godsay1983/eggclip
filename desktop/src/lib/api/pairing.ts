import { invoke } from "@tauri-apps/api/core";
import type {
  PairingJoinAttemptSummary,
  TrustedOutboundConnectionSummary,
} from "$lib/types/pairing";

export async function parsePairingJoinInvitation(
  invitation: string,
): Promise<PairingJoinAttemptSummary> {
  return invoke<PairingJoinAttemptSummary>("parse_pairing_join_invitation", {
    invitation,
  });
}

export async function cancelPairingJoinAttempt(attemptId: string): Promise<void> {
  await invoke("cancel_pairing_join_attempt", { attemptId });
}

export async function connectTrustedPeer(
  attemptId: string,
  options: { candidateId: string } | { manualHost: string; manualPort: number },
): Promise<TrustedOutboundConnectionSummary> {
  return invoke<TrustedOutboundConnectionSummary>("connect_trusted_peer", {
    attemptId,
    candidateId: "candidateId" in options ? options.candidateId : null,
    manualHost: "manualHost" in options ? options.manualHost : null,
    manualPort: "manualPort" in options ? options.manualPort : null,
  });
}
