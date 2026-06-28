import { writable } from "svelte/store";
import {
  defaultAppSettings,
  loadAppSettings,
  saveAppSettings,
  validateAppSettings,
} from "$lib/api/settings";
import type { AppSettings, SettingsSnapshot } from "$lib/types/settings";

const snapshot = writable<SettingsSnapshot>({
  state: "idle",
  settings: defaultAppSettings(),
  errorMessage: null,
});

async function saveSettingsSnapshot(settings: AppSettings) {
  const validationError = validateAppSettings(settings);
  if (validationError !== null) {
    snapshot.update((current) => ({
      ...current,
      state: "error",
      errorMessage: validationError,
    }));
    throw new Error(validationError);
  }

  snapshot.update((current) => ({
    ...current,
    state: "saving",
    settings,
    errorMessage: null,
  }));
  try {
    const saved = await saveAppSettings(settings);
    snapshot.set({
      state: "ready",
      settings: saved,
      errorMessage: null,
    });
  } catch (error) {
    snapshot.update((current) => ({
      ...current,
      state: "error",
      errorMessage: error instanceof Error ? error.message : "保存设置失败",
    }));
    throw error;
  }
}

export const settingsSnapshot = {
  subscribe: snapshot.subscribe,
  async load() {
    snapshot.update((current) => ({
      ...current,
      state: "loading",
      errorMessage: null,
    }));
    try {
      const settings = await loadAppSettings();
      snapshot.set({
        state: "ready",
        settings,
        errorMessage: null,
      });
    } catch (error) {
      snapshot.update((current) => ({
        ...current,
        state: "error",
        errorMessage: error instanceof Error ? error.message : "读取设置失败",
      }));
    }
  },
  async save(settings: AppSettings) {
    await saveSettingsSnapshot(settings);
  },
  async setSyncEnabled(syncEnabled: boolean) {
    let next = defaultAppSettings();
    const unsubscribe = snapshot.subscribe((current) => {
      next = {
        ...current.settings,
        syncEnabled,
      };
    });
    unsubscribe();
    await saveSettingsSnapshot(next);
  },
};
