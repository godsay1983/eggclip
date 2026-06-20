import { derived, writable } from "svelte/store";
import { createInitialShellSnapshot } from "$lib/api/shell";

const snapshot = writable(createInitialShellSnapshot());

export const shellSnapshot = {
  subscribe: snapshot.subscribe,
};

export const onlineDeviceCount = derived(snapshot, ($snapshot) =>
  $snapshot.devices.filter((device) => device.state === "online").length,
);
