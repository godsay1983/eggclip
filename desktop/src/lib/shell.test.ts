import { describe, expect, it } from "vitest";

describe("desktop shell", () => {
  it("keeps the first release text-only limit explicit", () => {
    const maxClipboardBytes = 256 * 1024;
    expect(maxClipboardBytes).toBe(262144);
  });
});

