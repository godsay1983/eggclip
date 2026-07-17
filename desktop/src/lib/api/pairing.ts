import { invoke } from "@tauri-apps/api/core";
import type { PairingJoinAttemptSummary } from "$lib/types/pairing";

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
