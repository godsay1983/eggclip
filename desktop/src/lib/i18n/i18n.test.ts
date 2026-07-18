import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  DEFAULT_LANGUAGE_MODE,
  DEFAULT_LOCALE,
  formatTime,
  formatUiMessage,
  isLanguageMode,
  pluralText,
  resolveEffectiveLocale,
  resolveSystemLocale,
  translate,
  text,
  uiMessage,
  enUSText,
  zhCNText,
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

  it("keeps every desktop text key and parameter aligned in both languages", () => {
    expect(Object.keys(enUSText).sort()).toEqual(Object.keys(zhCNText).sort());
    const placeholders = (value: string) =>
      [...value.matchAll(/\{([A-Za-z][A-Za-z0-9]*)\}/g)].map((match) => match[1]).sort();
    for (const key of Object.keys(zhCNText) as Array<keyof typeof zhCNText>) {
      expect(placeholders(enUSText[key]), key).toEqual(placeholders(zhCNText[key]));
    }
    expect(text("en-US", "pairing.progressCandidate", {
      current: 1,
      total: 3,
      endpoint: "192.168.1.8:43210",
    })).toBe("Trying address 1/3 · 192.168.1.8:43210");
  });

  it("uses English singular and plural forms for desktop counts and remaining time", () => {
    expect(pluralText("en-US", 1, "space.deviceCountOne", "space.deviceCountOther"))
      .toBe("1 trusted device");
    expect(pluralText("en-US", 2, "space.deviceCountOne", "space.deviceCountOther"))
      .toBe("2 trusted devices");
    expect(pluralText("en-US", 1, "pairing.validForOne", "pairing.validForOther", {
      minutes: 1,
      time: "10:30 AM",
    })).toContain("1 minute");
  });

  it("localizes generated space and device names while leaving custom names untouched", () => {
    expect(text("zh-CN", "space.generatedName", { id: "018ff6ef" }))
      .toBe("同步空间 #018ff6ef");
    expect(text("en-US", "space.generatedName", { id: "018ff6ef" }))
      .toBe("Sync space #018ff6ef");
    expect(text("zh-CN", "device.generatedName", { fingerprint: "Abc_123" }))
      .toBe("EggClip 设备 #Abc_123");
    expect(text("en-US", "device.generatedName", { fingerprint: "Abc_123" }))
      .toBe("EggClip device #Abc_123");
  });

  it("keeps Svelte components free of hard-coded Chinese and protects long copy layout", () => {
    const sourceRoot = fileURLToPath(new URL("../../", import.meta.url));
    const svelteFiles: string[] = [];
    const visit = (directory: string) => {
      for (const entry of readdirSync(directory, { withFileTypes: true })) {
        const path = `${directory}/${entry.name}`;
        if (entry.isDirectory()) visit(path);
        else if (entry.name.endsWith(".svelte")) svelteFiles.push(path);
      }
    };
    visit(sourceRoot);
    expect(svelteFiles.length).toBeGreaterThan(0);
    for (const path of svelteFiles) {
      expect(readFileSync(path, "utf8"), path).not.toMatch(/\p{Script=Han}/u);
    }

    const css = readFileSync(fileURLToPath(new URL("../../app.css", import.meta.url)), "utf8");
    expect(css).toContain("overflow-wrap: anywhere");
    expect(enUSText["device.removeHint"].length).toBeGreaterThan(100);
  });
});
