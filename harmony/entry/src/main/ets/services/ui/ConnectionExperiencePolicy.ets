import { ConnectionState } from '../../models/ShellModels';

export interface ConnectionExperiencePolicy {
  showFirstUse: boolean;
  showRetry: boolean;
  retryEnabled: boolean;
}

export function connectionExperiencePolicy(
  trustedDeviceCount: number,
  connectionState: ConnectionState,
  appInForeground: boolean,
  retrying: boolean
): ConnectionExperiencePolicy {
  const hasTrustedDevice = Number.isSafeInteger(trustedDeviceCount) && trustedDeviceCount > 0;
  const showRetry = hasTrustedDevice &&
    (connectionState === ConnectionState.OFFLINE || connectionState === ConnectionState.AUTH_FAILED);
  return {
    showFirstUse: !hasTrustedDevice,
    showRetry,
    retryEnabled: showRetry && appInForeground && !retrying
  };
}
