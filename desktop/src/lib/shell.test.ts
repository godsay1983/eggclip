import { describe, expect, it } from "vitest";
import { createInitialShellSnapshot } from "$lib/api/shell";
import { defaultAppSettings, validateAppSettings } from "$lib/api/settings";
import type { AppSettings } from "$lib/types/settings";
import { countOnlineDevices, mergeRuntimeDevices } from "$lib/stores/shell-state";
import type { DeviceSummary } from "$lib/types/shell";

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

  it("keeps desktop settings defaults and local validation aligned with v1 policy", () => {
    const settings = defaultAppSettings();

    expect(settings.syncEnabled).toBe(true);
    expect(settings.autoReceiveEnabled).toBe(true);
    expect(settings.autoWriteEnabled).toBe(true);
    expect(settings.historyLimit).toBe(50);
    expect(settings.retentionDays).toBe(7);
    expect(validateAppSettings(settings)).toBeNull();
    expect(
      validateAppSettings({
        ...settings,
        historyLimit: 10 as AppSettings["historyLimit"],
      }),
    ).not.toBeNull();
  });

  it("keeps authenticated endpoints out of the POC device list", () => {
    const trusted: DeviceSummary[] = [{
      id: "trusted-1",
      name: "Harmony",
      state: "online",
      trustKind: "trusted",
      shortFingerprint: "12345678",
      lastSeen: "当前会话在线",
      endpoint: "192.168.1.9:4567",
      note: "认证会话在线",
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

  it("returns a single offline placeholder when no runtime device exists", () => {
    const devices = mergeRuntimeDevices([], [], new Set());

    expect(devices).toHaveLength(1);
    expect(devices[0].trustKind).toBe("placeholder");
    expect(countOnlineDevices(devices)).toBe(0);
  });
});
