export interface ConnectionExperiencePolicy {
  showFirstUse: boolean;
  showRetry: boolean;
  retryEnabled: boolean;
}

export function connectionExperiencePolicy(
  trustedDeviceCount: number,
  connectionTitle: string,
  appInForeground: boolean,
  retrying: boolean
): ConnectionExperiencePolicy {
  const hasTrustedDevice = Number.isSafeInteger(trustedDeviceCount) && trustedDeviceCount > 0;
  const showRetry = hasTrustedDevice &&
    (connectionTitle.indexOf('失败') >= 0 || connectionTitle.indexOf('断开') >= 0);
  return {
    showFirstUse: !hasTrustedDevice,
    showRetry,
    retryEnabled: showRetry && appInForeground && !retrying
  };
}
