import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));

const resourcePairs = [
  [
    "Harmony AppScope",
    "harmony/AppScope/resources/base/element/string.json",
    "harmony/AppScope/resources/zh_CN/element/string.json",
    ["app_name"],
  ],
  [
    "Harmony entry",
    "harmony/entry/src/main/resources/base/element/string.json",
    "harmony/entry/src/main/resources/zh_CN/element/string.json",
    [
      "module_desc",
      "EntryAbility_desc",
      "EntryAbility_label",
      "permission_internet_reason",
      "permission_network_info_reason",
      "language_system",
      "language_zh_cn",
      "language_en_us",
      "language_preview",
    ],
  ],
];

const harmonyPagePaths = [
  "harmony/entry/src/main/ets/pages/Index.ets",
  "harmony/entry/src/main/ets/pages/HomePage.ets",
  "harmony/entry/src/main/ets/pages/DevicesPage.ets",
  "harmony/entry/src/main/ets/pages/PairingPage.ets",
  "harmony/entry/src/main/ets/pages/SettingsPage.ets",
];

for (const [label, basePath, chinesePath, requiredKeys] of resourcePairs) {
  const baseKeys = readResourceKeys(basePath);
  const chineseKeys = readResourceKeys(chinesePath);
  assertEqualKeys(label, baseKeys, chineseKeys);
  for (const key of requiredKeys) {
    if (!baseKeys.includes(key)) {
      throw new Error(`${label}: missing required resource ${key}`);
    }
  }
}

const entryKeys = readResourceKeys("harmony/entry/src/main/resources/base/element/string.json");
const entryKeySet = new Set(entryKeys);
for (const pagePath of harmonyPagePaths) {
  const source = readFileSync(resolve(repoRoot, pagePath), "utf8");
  for (const match of source.matchAll(/\$r\('app\.string\.([A-Za-z0-9_]+)'\)/g)) {
    if (!entryKeySet.has(match[1])) {
      throw new Error(`${pagePath}: missing resource key ${match[1]}`);
    }
  }
  if (/(?:Text|Button|accessibilityText)\(\s*'[^'\r\n]*[\u3400-\u9fff]/u.test(source)) {
    throw new Error(`${pagePath}: visible static Chinese text must use a string resource`);
  }
}

assertIncludes(
  "harmony/entry/src/main/ets/pages/HomePage.ets",
  ["GridRow", "sm: 12", "md: 6", "maxWidth: 960"],
);
assertIncludes(
  "harmony/entry/src/main/ets/pages/DevicesPage.ets",
  ["GridRow", "sm: 12", "md: 5", "md: 7", "maxWidth: 960"],
);
assertIncludes(
  "harmony/entry/src/main/ets/pages/SettingsPage.ets",
  ["GridRow", "sm: 12", "md: 6", "maxWidth: 960"],
);

process.stdout.write("i18n foundation resources ok\n");

function readResourceKeys(relativePath) {
  const content = JSON.parse(readFileSync(resolve(repoRoot, relativePath), "utf8"));
  if (!Array.isArray(content.string)) {
    throw new Error(`${relativePath}: string resource array is missing`);
  }
  const keys = content.string.map((entry) => entry.name);
  if (new Set(keys).size !== keys.length) {
    throw new Error(`${relativePath}: duplicate string resource name`);
  }
  return keys.sort();
}

function assertEqualKeys(label, baseKeys, localizedKeys) {
  if (baseKeys.join("\n") !== localizedKeys.join("\n")) {
    throw new Error(`${label}: base and zh_CN resource keys differ`);
  }
}

function assertIncludes(relativePath, requiredFragments) {
  const source = readFileSync(resolve(repoRoot, relativePath), "utf8");
  for (const fragment of requiredFragments) {
    if (!source.includes(fragment)) {
      throw new Error(`${relativePath}: missing responsive layout fragment ${fragment}`);
    }
  }
}
