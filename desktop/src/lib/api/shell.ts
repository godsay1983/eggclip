import type { ShellSnapshot } from "$lib/types/shell";

export function createInitialShellSnapshot(): ShellSnapshot {
  return {
    connection: {
      state: "offline",
      title: "等待配对设备",
      description: "桌面端将在局域网中自动发现可信设备",
    },
    current: null,
    devices: [
      {
        id: "placeholder",
        name: "等待配对设备",
        state: "offline",
      },
    ],
    history: {
      used: 0,
      limit: 50,
    },
    syncEnabled: true,
  };
}
