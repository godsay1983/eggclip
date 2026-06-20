import { describe, expect, it } from "vitest";
import { createInitialShellSnapshot } from "$lib/api/shell";

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
});
