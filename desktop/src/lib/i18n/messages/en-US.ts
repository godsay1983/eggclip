import type { MessageCatalog } from "$lib/i18n/types";

export const enUSMessages: MessageCatalog = {
  "language.system": () => "System",
  "language.zhCN": () => "简体中文",
  "language.enUS": () => "English",
  "language.preview": (appName) => `${appName} is now using English`,
};
