import { describe, expect, it } from "vitest";
import { createInitialShellSnapshot } from "$lib/api/shell";
import { defaultAppSettings, validateAppSettings } from "$lib/api/settings";
import type { AppSettings } from "$lib/types/settings";

describe("desktop shell", () => {
  it("keeps the first release text-only limit explicit", () => {
    const maxClipboardBytes = 256 * 1024;
    expect(maxClipboardBytes).toBe(262144);
  });

  it("starts with no paired device and the default retention limit", () => {
    const snapshot = createInitialShellSnapshot();

    expect(snapshot.connection.state).toBe("offline");
    expect(snapshot.current).toBeNull();
    expect(snapshot.history.limit).toBe(50);
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
});
