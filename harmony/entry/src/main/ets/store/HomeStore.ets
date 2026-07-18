import { ConnectionState, HomeShellState } from '../models/ShellModels';
import { UiMessageCode, uiMessage } from '../services/localization/UiMessageCodes';

export function createInitialHomeShellState(): HomeShellState {
  return {
    connection: {
      state: ConnectionState.OFFLINE,
      title: uiMessage(UiMessageCode.CONNECTION_WAITING_TITLE),
      description: uiMessage(UiMessageCode.CONNECTION_WAITING_DESCRIPTION)
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
