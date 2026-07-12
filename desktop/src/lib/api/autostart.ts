import {
  disable as disableSystemAutostart,
  enable as enableSystemAutostart,
  isEnabled as isSystemAutostartEnabled,
} from "@tauri-apps/plugin-autostart";

export interface AutostartGateway {
  isEnabled(): Promise<boolean>;
  enable(): Promise<void>;
  disable(): Promise<void>;
}

export const systemAutostartGateway: AutostartGateway = {
  isEnabled: isSystemAutostartEnabled,
  enable: enableSystemAutostart,
  disable: disableSystemAutostart,
};
