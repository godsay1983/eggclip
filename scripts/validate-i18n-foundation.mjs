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
  const baseResources = readStringResources(basePath);
  const chineseResources = readStringResources(chinesePath);
  const baseKeys = [...baseResources.keys()].sort();
  const chineseKeys = [...chineseResources.keys()].sort();
  assertEqualKeys(label, baseKeys, chineseKeys);
  assertPlaceholderParity(label, baseResources, chineseResources);
  for (const key of requiredKeys) {
    if (!baseKeys.includes(key)) {
      throw new Error(`${label}: missing required resource ${key}`);
    }
  }
}

const entryKeys = [...readStringResources("harmony/entry/src/main/resources/base/element/string.json").keys()].sort();
const entryKeySet = new Set(entryKeys);
const basePlurals = readPluralResources("harmony/entry/src/main/resources/base/element/plural.json");
const chinesePlurals = readPluralResources("harmony/entry/src/main/resources/zh_CN/element/plural.json");
assertEqualKeys("Harmony entry plurals", [...basePlurals.keys()].sort(), [...chinesePlurals.keys()].sort());
assertPluralPlaceholderParity(basePlurals, chinesePlurals);
const pluralKeySet = new Set(basePlurals.keys());
for (const pagePath of harmonyPagePaths) {
  const source = readFileSync(resolve(repoRoot, pagePath), "utf8");
  for (const match of source.matchAll(/\$r\('app\.string\.([A-Za-z0-9_]+)'\)/g)) {
    if (!entryKeySet.has(match[1])) {
      throw new Error(`${pagePath}: missing resource key ${match[1]}`);
    }
  }
  for (const match of source.matchAll(/resourceText\('([A-Za-z0-9_]+)'/g)) {
    if (!entryKeySet.has(match[1])) {
      throw new Error(`${pagePath}: missing dynamic resource key ${match[1]}`);
    }
  }
  for (const match of source.matchAll(/pluralText\('([A-Za-z0-9_]+)'/g)) {
    if (!pluralKeySet.has(match[1])) {
      throw new Error(`${pagePath}: missing plural resource key ${match[1]}`);
    }
  }
  if (/[\u3400-\u9fff]/u.test(source)) {
    throw new Error(`${pagePath}: page-level Chinese text must use a resource`);
  }
}

const dynamicSourcePaths = [
  "harmony/entry/src/main/ets/store/PairingStore.ets",
  "harmony/entry/src/main/ets/store/PocConnectionStore.ets",
  "harmony/entry/src/main/ets/store/HistoryStore.ets",
  "harmony/entry/src/main/ets/store/TrustedDeviceStore.ets",
  "harmony/entry/src/main/ets/store/SettingsStore.ets",
  "harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets",
];
for (const sourcePath of dynamicSourcePaths) {
  const source = readFileSync(resolve(repoRoot, sourcePath), "utf8");
  if (/[\u3400-\u9fff]/u.test(source)) {
    throw new Error(`${sourcePath}: Store and transport status must use stable codes`);
  }
}

const pairingConnectionSource = readFileSync(
  resolve(repoRoot, "harmony/entry/src/main/ets/store/PairingConnectionStore.ets"),
  "utf8",
).replace(/`同步空间 #\$\{shortId\(spaceId\)\}`/g, "")
  .replace(/`桌面端 #\$\{shortId\(serverHello\.deviceId\)\}`/g, "");
if (/[\u3400-\u9fff]/u.test(pairingConnectionSource)) {
  throw new Error("PairingConnectionStore: only I18N-07 generated-name literals may remain localized");
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

function readStringResources(relativePath) {
  const content = JSON.parse(readFileSync(resolve(repoRoot, relativePath), "utf8"));
  if (!Array.isArray(content.string)) {
    throw new Error(`${relativePath}: string resource array is missing`);
  }
  const keys = content.string.map((entry) => entry.name);
  if (new Set(keys).size !== keys.length) {
    throw new Error(`${relativePath}: duplicate string resource name`);
  }
  return new Map(content.string.map((entry) => [entry.name, entry.value]));
}

function readPluralResources(relativePath) {
  const content = JSON.parse(readFileSync(resolve(repoRoot, relativePath), "utf8"));
  if (!Array.isArray(content.plural)) {
    throw new Error(`${relativePath}: plural resource array is missing`);
  }
  const keys = content.plural.map((entry) => entry.name);
  if (new Set(keys).size !== keys.length) {
    throw new Error(`${relativePath}: duplicate plural resource name`);
  }
  return new Map(content.plural.map((entry) => [entry.name, entry.value]));
}

function assertEqualKeys(label, baseKeys, localizedKeys) {
  if (baseKeys.join("\n") !== localizedKeys.join("\n")) {
    throw new Error(`${label}: base and zh_CN resource keys differ`);
  }
}

function placeholders(value) {
  return [...value.matchAll(/%(?:\d+\$)?[ds]/g)].map((match) => match[0].replace(/\d+\$/, ""));
}

function assertPlaceholderParity(label, baseResources, localizedResources) {
  for (const [key, value] of baseResources) {
    const base = placeholders(value).join(",");
    const localized = placeholders(localizedResources.get(key) ?? "").join(",");
    if (base !== localized) {
      throw new Error(`${label}: placeholder mismatch for ${key}`);
    }
  }
}

function assertPluralPlaceholderParity(baseResources, localizedResources) {
  for (const [key, baseValues] of baseResources) {
    const localizedValues = localizedResources.get(key) ?? [];
    const base = [...new Set(baseValues.flatMap((entry) => placeholders(entry.value)))].join(",");
    const localized = [...new Set(localizedValues.flatMap((entry) => placeholders(entry.value)))].join(",");
    if (base !== localized) {
      throw new Error(`Harmony entry plurals: placeholder mismatch for ${key}`);
    }
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
