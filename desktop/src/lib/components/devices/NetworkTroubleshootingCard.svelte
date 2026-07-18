<script lang="ts">
  import { effectiveLocale, text } from "$lib/i18n";
  import type { PocTransportSummary } from "$lib/types/shell";

  export let transport: PocTransportSummary = {
    state: "stopped",
    port: 0,
    discoveryPublished: false,
    networkAddresses: [],
    discoveredServices: [],
    connectedPeers: 0,
    lastError: null,
  };

  $: hasTunnelAddress = transport.networkAddresses.some((item) => item.isTunnel);
  $: hasNormalAddress = transport.networkAddresses.some((item) => !item.isTunnel);
  $: canShareEndpoint = transport.state === "running" && transport.port > 0 && hasNormalAddress;

  function primaryHint(): string {
    if (transport.state === "failed") {
      return text($effectiveLocale, "network.startFailed");
    }
    if (!hasNormalAddress && hasTunnelAddress) {
      return text($effectiveLocale, "network.onlyTunnel");
    }
    if (!transport.discoveryPublished) {
      return text($effectiveLocale, "network.mdnsFailed");
    }
    if (canShareEndpoint) {
      return text($effectiveLocale, "network.manualReady");
    }
    return text($effectiveLocale, "network.waiting");
  }

  function firstNormalAddress(): string {
    return transport.networkAddresses.find((item) => !item.isTunnel)?.address ?? text($effectiveLocale, "network.noNormalIpv4");
  }
</script>

<section class="poc-connect-card" aria-labelledby="network-troubleshooting-title">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">{text($effectiveLocale, "network.troubleshoot")}</span>
      <h2 id="network-troubleshooting-title">{text($effectiveLocale, "network.manualCheck")}</h2>
    </div>
  </div>

  <p>{primaryHint()}</p>

  <div class="history-list" aria-label={text($effectiveLocale, "network.items")}>
    <article class="history-item">
      <strong>{text($effectiveLocale, "network.manualEndpoint")}</strong>
      <p>{firstNormalAddress()} · {text($effectiveLocale, "network.portValue", { port: transport.port > 0 ? transport.port : text($effectiveLocale, "common.unassigned") })}</p>
    </article>
    <article class="history-item">
      <strong>{text($effectiveLocale, "network.firewall")}</strong>
      <p>{text($effectiveLocale, "network.firewallHint")}</p>
    </article>
    <article class="history-item">
      <strong>{text($effectiveLocale, "network.apIsolation")}</strong>
      <p>{text($effectiveLocale, "network.apHint")}</p>
    </article>
    <article class="history-item">
      <strong>VPN/TUN</strong>
      <p>{text($effectiveLocale, hasTunnelAddress ? "network.tunnelFound" : "network.tunnelMissing")}</p>
    </article>
  </div>
</section>
