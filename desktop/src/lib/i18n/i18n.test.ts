import { describe, expect, it } from "vitest";
import {
  DEFAULT_LANGUAGE_MODE,
  DEFAULT_LOCALE,
  formatTime,
  isLanguageMode,
  resolveEffectiveLocale,
  resolveSystemLocale,
  translate,
} from "$lib/i18n";

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
});
