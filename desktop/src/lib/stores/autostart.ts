import { writable } from "svelte/store";
import {
  systemAutostartGateway,
  type AutostartGateway,
} from "$lib/api/autostart";
import type { AutostartSnapshot } from "$lib/types/autostart";

export function createAutostartStore(
  gateway: AutostartGateway = systemAutostartGateway,
) {
  const snapshot = writable<AutostartSnapshot>({
    state: "idle",
    enabled: false,
    errorMessage: null,
  });

  return {
    subscribe: snapshot.subscribe,
    async load() {
      snapshot.update((current) => ({
        ...current,
        state: "loading",
        errorMessage: null,
      }));
      try {
        const enabled = await gateway.isEnabled();
        snapshot.set({ state: "ready", enabled, errorMessage: null });
      } catch (_) {
        snapshot.update((current) => ({
          ...current,
          state: "error",
          errorMessage: "无法读取 Windows 开机启动状态。",
        }));
      }
    },
    async setEnabled(enabled: boolean) {
      let previousEnabled = false;
      const unsubscribe = snapshot.subscribe((current) => {
        previousEnabled = current.enabled;
      });
      unsubscribe();

      snapshot.set({ state: "saving", enabled, errorMessage: null });
      try {
        if (enabled) {
          await gateway.enable();
        } else {
          await gateway.disable();
        }
        const actualEnabled = await gateway.isEnabled();
        if (actualEnabled !== enabled) {
          throw new Error("autostart state mismatch");
        }
        snapshot.set({ state: "ready", enabled: actualEnabled, errorMessage: null });
      } catch (_) {
        snapshot.set({
          state: "error",
          enabled: previousEnabled,
          errorMessage: "无法修改开机启动，请检查 Windows 系统权限。",
        });
      }
    },
  };
}

export const autostartSnapshot = createAutostartStore();
