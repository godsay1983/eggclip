import { describe, expect, it } from "vitest";
import {
  DEFAULT_LANGUAGE_MODE,
  DEFAULT_LOCALE,
  formatTime,
  formatUiMessage,
  isLanguageMode,
  resolveEffectiveLocale,
  resolveSystemLocale,
  translate,
  uiMessage,
} from "$lib/i18n";
import type { UiMessageCode } from "$lib/i18n";

describe("desktop i18n foundation", () => {
  it("keeps the fixed language modes and fallback explicit", () => {
    expect(DEFAULT_LANGUAGE_MODE).toBe("system");
    expect(DEFAULT_LOCALE).toBe("en-US");
    expect(isLanguageMode("system")).toBe(true);
    expect(isLanguageMode("zh-CN")).toBe(true);
    expect(isLanguageMode("en-US")).toBe(true);
    expect(isLanguageMode("fr-FR")).toBe(false);
  });

  it("resolves Chinese and English system preferences with an English fallback", () => {
    expect(resolveSystemLocale(["zh-Hans-CN", "en-US"])).toBe("zh-CN");
    expect(resolveSystemLocale(["en-GB"])).toBe("en-US");
    expect(resolveSystemLocale(["fr-FR"])).toBe("en-US");
    expect(resolveEffectiveLocale("zh-CN", ["en-US"])).toBe("zh-CN");
    expect(resolveEffectiveLocale("system", ["zh-CN"])).toBe("zh-CN");
  });

  it("switches the minimal typed catalog without changing the message key", () => {
    expect(translate("zh-CN", "language.preview", "EggClip")).toBe(
      "EggClip 已切换为简体中文",
    );
    expect(translate("en-US", "language.preview", "EggClip")).toBe(
      "EggClip is now using English",
    );
  });

  it("formats time with the selected locale", () => {
    const value = new Date(2026, 0, 2, 15, 4, 5);
    expect(formatTime(value, "zh-CN").length).toBeGreaterThan(0);
    expect(formatTime(value, "en-US").length).toBeGreaterThan(0);
  });

  it("re-renders an existing status descriptor after a language switch", () => {
    const descriptor = uiMessage("sync.sentDescription", { count: 2 });
    expect(formatUiMessage("zh-CN", descriptor)).toContain("2 个可信设备");
    expect(formatUiMessage("en-US", descriptor)).toContain("2 trusted devices");
  });

  it("falls back for unknown codes and rejects sensitive parameter names", () => {
    expect(formatUiMessage("en-US", {
      code: "unknown.code" as UiMessageCode,
      params: {},
    })).toBe("The operation failed. Please try again.");
    expect(() => uiMessage("sync.sentDescription", { content: "clipboard text" }))
      .toThrow("unsafe ui message parameter");
  });
});
