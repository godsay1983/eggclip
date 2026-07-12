import type { DeviceSummary } from "$lib/types/shell";

export function mergeRuntimeDevices(
  trustedDevices: DeviceSummary[],
  pocPeerEndpoints: string[],
  authenticatedPeerEndpoints: Set<string>,
): DeviceSummary[] {
  const trustedEndpoints = new Set(
    trustedDevices
      .map((device) => device.endpoint)
      .filter((endpoint): endpoint is string => endpoint !== undefined),
  );
  const pocDevices = [...new Set(pocPeerEndpoints)]
    .filter((peer) => !authenticatedPeerEndpoints.has(peer) && !trustedEndpoints.has(peer))
    .sort()
    .map(
      (peer): DeviceSummary => ({
        id: `poc-${peer}`,
        name: "远端 POC 连接",
        state: "online",
        trustKind: "poc",
        shortFingerprint: "未配对",
        lastSeen: "当前会话在线",
        endpoint: peer,
        note: "实验连接尚未完成设备身份认证，仅用于手动收发验证。",
      }),
    );
  const devices = [...trustedDevices, ...pocDevices];
  return devices.length > 0
    ? devices
    : [
        {
          id: "placeholder",
          name: "等待可信设备",
          state: "offline",
          trustKind: "placeholder",
          shortFingerprint: "等待配对",
          lastSeen: "暂无",
          note: "正式配对完成后，这里会显示设备名称、公钥短指纹和最后在线时间。",
        },
      ];
}

export function countOnlineDevices(devices: DeviceSummary[]): number {
  return devices.filter((device) => device.state === "online" && device.trustKind === "trusted").length;
}
