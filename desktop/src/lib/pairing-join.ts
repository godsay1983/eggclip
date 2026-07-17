import type { PairingJoinAddressSummary, PairingJoinAttemptSummary } from "$lib/types/pairing";

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
  title: string;
  message: string;
  retryableNetwork: boolean;
}

export function pairingErrorMessage(error: unknown): string {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  return "配对失败，请重新生成邀请后再试";
}

export function classifyPairingJoinError(error: unknown): PairingJoinIssue {
  const message = pairingErrorMessage(error);
  if (message.includes("已过期")) {
    return { title: "邀请已过期", message, retryableNetwork: false };
  }
  if (message.includes("已使用") || message.includes("找不到该邀请")) {
    return { title: "邀请不可用", message, retryableNetwork: false };
  }
  if (message.includes("身份") || message.includes("连接的是生成邀请的电脑")) {
    return { title: "设备身份不匹配", message, retryableNetwork: false };
  }
  if (message.includes("密钥") || message.includes("凭据")) {
    return { title: "密钥保存失败", message, retryableNetwork: false };
  }
  if (message.includes("数据库")) {
    return { title: "本机保存失败", message, retryableNetwork: false };
  }
  if (
    message.includes("无法连接") ||
    message.includes("连接可信设备超时") ||
    message.includes("握手超时") ||
    message.includes("不可达") ||
    message.includes("防火墙")
  ) {
    return { title: "网络不可达", message, retryableNetwork: true };
  }
  if (message.includes("认证") || message.includes("握手")) {
    return { title: "认证失败", message, retryableNetwork: false };
  }
  return { title: "配对失败", message, retryableNetwork: false };
}

export function prioritizedPairingAddresses(
  addresses: PairingJoinAddressSummary[],
  preferredCandidateId: string,
): PairingJoinAddressSummary[] {
  const preferred = addresses.find((address) => address.candidateId === preferredCandidateId);
  if (!preferred) return [...addresses];
  return [preferred, ...addresses.filter((address) => address.candidateId !== preferredCandidateId)];
}
