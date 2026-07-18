import { describe, expect, it } from "vitest";
import {
  createInitialShellSnapshot,
  toAuthenticatedClipboardPreview,
} from "$lib/api/shell";
import { defaultAppSettings, validateAppSettings } from "$lib/api/settings";
import { createAutostartStore } from "$lib/stores/autostart";
import type { AutostartSnapshot } from "$lib/types/autostart";
import type { AppSettings } from "$lib/types/settings";
import { countOnlineDevices, mergeRuntimeDevices } from "$lib/stores/shell-state";
import {
  canManageSyncSpace,
  classifyPairingJoinError,
  emptyPairingJoinFormState,
  prioritizedPairingAddresses,
  readyPairingJoinFormState,
} from "$lib/pairing-join";
import type { DeviceSummary } from "$lib/types/shell";
import { formatUiMessage } from "$lib/i18n";

describe("desktop shell", () => {
  it("keeps the first release text-only limit explicit", () => {
    const maxClipboardBytes = 256 * 1024;
    expect(maxClipboardBytes).toBe(262144);
  });

  it("starts with no paired device and the default retention limit", () => {
    const snapshot = createInitialShellSnapshot();

    expect(snapshot.connection.state).toBe("offline");
    expect(snapshot.current).toBeNull();
    expect(snapshot.outbound.state).toBe("idle");
    expect(snapshot.lastPocEndpoint).toBeNull();
    expect(snapshot.history.limit).toBe(50);
    expect(snapshot.history.items).toEqual([]);
    expect(snapshot.devices).toHaveLength(1);
    expect(snapshot.devices[0].id).toBe("placeholder");
  });

  it("maps authenticated Harmony text directly into the desktop preview", () => {
    const preview = toAuthenticatedClipboardPreview({
      peer: "192.168.1.9:4567",
      itemId: "item-1",
      originDeviceId: "15a91e5a-1234-5678-9012-123456789012",
      originSeq: 7,
      item: {
        text: "来自 Harmony 的文本",
        byteLen: 24,
        digest: 42,
      },
    });

    expect(preview.id).toBe("item-1");
    expect(preview.text).toBe("来自 Harmony 的文本");
    expect(preview.sourceKind).toBe("trusted");
    expect(preview.sourceDevice).toBe("15a91e5a");
    expect(preview.byteLength).toBe(24);
  });

  it("keeps desktop settings defaults and local validation aligned with v1 policy", () => {
    const settings = defaultAppSettings();

    expect(settings.syncEnabled).toBe(true);
    expect(settings.autoReceiveEnabled).toBe(true);
    expect(settings.autoWriteEnabled).toBe(true);
    expect(settings.historyLimit).toBe(50);
    expect(settings.retentionDays).toBe(7);
    expect(settings.languageMode).toBe("system");
    expect(validateAppSettings(settings)).toBeNull();
    expect(
      validateAppSettings({
        ...settings,
        historyLimit: 10 as AppSettings["historyLimit"],
      }),
    ).not.toBeNull();
  });

  it("reads and updates the actual Windows autostart state", async () => {
    let systemEnabled = false;
    const store = createAutostartStore({
      async isEnabled() {
        return systemEnabled;
      },
      async enable() {
        systemEnabled = true;
      },
      async disable() {
        systemEnabled = false;
      },
    });
    let current: AutostartSnapshot = {
      state: "idle",
      enabled: false,
      errorMessage: null,
    };
    const unsubscribe = store.subscribe((snapshot) => {
      current = snapshot;
    });

    await store.load();
    expect(current.state).toBe("ready");
    expect(current.enabled).toBe(false);

    await store.setEnabled(true);
    expect(systemEnabled).toBe(true);
    expect(current.enabled).toBe(true);

    await store.setEnabled(false);
    expect(systemEnabled).toBe(false);
    expect(current.enabled).toBe(false);
    unsubscribe();
  });

  it("keeps authenticated endpoints out of the POC device list", () => {
    const trusted: DeviceSummary[] = [{
      id: "trusted-1",
      name: "Harmony",
      state: "online",
      trustKind: "trusted",
      shortFingerprint: "12345678",
      endpoint: "192.168.1.9:4567",
      lastSeenAtMs: Date.now(),
    }];
    const devices = mergeRuntimeDevices(
      trusted,
      ["192.168.1.9:4567", "192.168.1.10:4567", "192.168.1.10:4567"],
      new Set(["192.168.1.9:4567"]),
    );

    expect(devices).toHaveLength(2);
    expect(devices[0].trustKind).toBe("trusted");
    expect(devices[1].id).toBe("poc-192.168.1.10:4567");
    expect(countOnlineDevices(devices)).toBe(1);
  });

  it("prioritizes the selected pairing address without losing fallbacks", () => {
    const addresses = [
      { candidateId: "address-1", displayAddress: "192.168.*.*:4567" },
      { candidateId: "address-2", displayAddress: "10.0.*.*:4567" },
    ];
    expect(prioritizedPairingAddresses(addresses, "address-2")).toEqual([
      addresses[1],
      addresses[0],
    ]);
  });

  it("distinguishes pairing failures that require different user actions", () => {
    const expired = classifyPairingJoinError({
      code: "pairingInvitationExpired",
      retryable: false,
      params: {},
    });
    expect(expired.title.code).toBe("pairing.invitationExpiredTitle");
    expect(formatUiMessage("en-US", expired.title)).toBe("Invitation expired");
    expect(classifyPairingJoinError({
      code: "pairingNetworkUnavailable",
      retryable: true,
      params: {},
    })).toMatchObject({
      retryableNetwork: true,
    });
    expect(classifyPairingJoinError("旧版中文错误").title.code).toBe("pairing.failedTitle");
  });

  it("clears join material after close or success and restores a validated address choice", () => {
    const cleared = emptyPairingJoinFormState();
    expect(cleared).toMatchObject({
      invitationText: "",
      selectedCandidateId: "",
      confirmationMatches: false,
      manualHost: "",
    });
    const ready = readyPairingJoinFormState({
      attemptId: "attempt-1",
      issuerDeviceName: "EggClip A",
      issuerShortFingerprint: "12345678",
      spaceShortId: "87654321",
      expiresAtMs: Date.now() + 60_000,
      expiresInSeconds: 60,
      confirmationCode: "123456",
      addresses: [{ candidateId: "address-1", displayAddress: "192.168.*.*:4567" }],
    });
    expect(ready.invitationText).toBe("");
    expect(ready.selectedCandidateId).toBe("address-1");
    expect(ready.confirmationMatches).toBe(false);
  });

  it("keeps owner and member device actions separated", () => {
    expect(canManageSyncSpace("owner", "invite")).toBe(true);
    expect(canManageSyncSpace("owner", "remove")).toBe(true);
    expect(canManageSyncSpace("owner", "leave")).toBe(false);
    expect(canManageSyncSpace("member", "invite")).toBe(false);
    expect(canManageSyncSpace("member", "remove")).toBe(false);
    expect(canManageSyncSpace("member", "leave")).toBe(true);
  });

  it("returns a single offline placeholder when no runtime device exists", () => {
    const devices = mergeRuntimeDevices([], [], new Set());

    expect(devices).toHaveLength(1);
    expect(devices[0].trustKind).toBe("placeholder");
    expect(countOnlineDevices(devices)).toBe(0);
  });
});
