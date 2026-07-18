import { uiMessage, type UiMessageDescriptor } from "$lib/i18n";
import type {
  AppErrorCode,
  AppErrorDto,
  PairingJoinAddressSummary,
  PairingJoinAttemptSummary,
} from "$lib/types/pairing";

export interface PairingJoinFormState {
  invitationText: string;
  selectedCandidateId: string;
  confirmationMatches: boolean;
  manualHost: string;
  manualPort: number;
  useManualAddress: boolean;
}

export function emptyPairingJoinFormState(): PairingJoinFormState {
  return {
    invitationText: "",
    selectedCandidateId: "",
    confirmationMatches: false,
    manualHost: "",
    manualPort: 4567,
    useManualAddress: false,
  };
}

export function readyPairingJoinFormState(
  attempt: PairingJoinAttemptSummary,
): PairingJoinFormState {
  return {
    ...emptyPairingJoinFormState(),
    selectedCandidateId: attempt.addresses[0]?.candidateId ?? "",
    useManualAddress: attempt.addresses.length === 0,
  };
}

export function canManageSyncSpace(
  role: "owner" | "member",
  action: "invite" | "remove" | "leave",
): boolean {
  return role === "owner" ? action !== "leave" : action === "leave";
}

export interface PairingJoinIssue {
  title: UiMessageDescriptor;
  message: UiMessageDescriptor;
  retryableNetwork: boolean;
}

export function isAppErrorDto(error: unknown): error is AppErrorDto {
  if (typeof error !== "object" || error === null) return false;
  const value = error as Partial<AppErrorDto>;
  return typeof value.code === "string" && typeof value.retryable === "boolean";
}

export function classifyPairingJoinError(error: unknown): PairingJoinIssue {
  const code: AppErrorCode = isAppErrorDto(error) ? error.code : "pairingFailed";
  const retryableNetwork = isAppErrorDto(error) && error.retryable;
  switch (code) {
    case "pairingInvitationEmpty":
      return issue("pairing.failedTitle", "pairing.invitationEmptyDescription", false);
    case "pairingInvitationTooLarge":
      return issue("pairing.failedTitle", "pairing.invitationTooLargeDescription", false);
    case "pairingInvitationInvalid":
    case "pairingInvalidEndpoint":
      return issue("pairing.failedTitle", "pairing.invitationInvalidDescription", false);
    case "pairingInvitationExpired":
      return issue("pairing.invitationExpiredTitle", "pairing.invitationExpiredDescription", false);
    case "pairingInvitationUnavailable":
      return issue("pairing.invitationUnavailableTitle", "pairing.invitationUnavailableDescription", false);
    case "pairingIdentityMismatch":
      return issue("pairing.identityMismatchTitle", "pairing.identityMismatchDescription", false);
    case "pairingCredentialFailed":
      return issue("pairing.credentialFailedTitle", "pairing.credentialFailedDescription", false);
    case "pairingStorageFailed":
      return issue("pairing.storageFailedTitle", "pairing.storageFailedDescription", false);
    case "pairingNetworkUnavailable":
      return issue("pairing.networkFailedTitle", "pairing.networkFailedDescription", true);
    case "pairingAuthenticationFailed":
      return issue("pairing.authenticationFailedTitle", "pairing.authenticationFailedDescription", false);
    case "pairingBusy":
    case "pairingFailed":
    default:
      return issue("pairing.failedTitle", "pairing.failedDescription", retryableNetwork);
  }
}

function issue(
  title: Parameters<typeof uiMessage>[0],
  message: Parameters<typeof uiMessage>[0],
  retryableNetwork: boolean,
): PairingJoinIssue {
  return { title: uiMessage(title), message: uiMessage(message), retryableNetwork };
}

export function prioritizedPairingAddresses(
  addresses: PairingJoinAddressSummary[],
  preferredCandidateId: string,
): PairingJoinAddressSummary[] {
  const preferred = addresses.find((address) => address.candidateId === preferredCandidateId);
  if (!preferred) return [...addresses];
  return [preferred, ...addresses.filter((address) => address.candidateId !== preferredCandidateId)];
}
