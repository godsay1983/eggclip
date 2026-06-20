import { ConnectionState, HomeShellState } from '../models/ShellModels';

export function createInitialHomeShellState(): HomeShellState {
  return {
    connection: {
      state: ConnectionState.OFFLINE,
      title: '等待配对设备',
      description: '前台打开后将自动发现局域网桌面端'
    },
    latest: null,
    devices: [
      {
        id: 'placeholder',
        name: '等待配对设备',
        state: ConnectionState.OFFLINE
      }
    ],
    history: {
      used: 0,
      limit: 50
    },
    syncEnabled: true
  };
}
