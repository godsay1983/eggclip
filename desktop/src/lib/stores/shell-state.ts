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
        name: "",
        state: "online",
        trustKind: "poc",
        shortFingerprint: "",
        endpoint: peer,
      }),
    );
  const devices = [...trustedDevices, ...pocDevices];
  return devices.length > 0
    ? devices
    : [
        {
          id: "placeholder",
          name: "",
          state: "offline",
          trustKind: "placeholder",
          shortFingerprint: "",
        },
      ];
}

export function countOnlineDevices(devices: DeviceSummary[]): number {
  return devices.filter((device) => device.state === "online" && device.trustKind === "trusted").length;
}
