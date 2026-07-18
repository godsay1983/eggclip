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
  export let onRefresh: () => Promise<void> | void = () => {};

  let refreshing = false;

  async function refresh(): Promise<void> {
    refreshing = true;
    try {
      await onRefresh();
    } finally {
      refreshing = false;
    }
  }

  function stateLabel(state: PocTransportSummary["state"]): string {
    if (state === "running") {
      return text($effectiveLocale, "network.running");
    }
    if (state === "failed") {
      return text($effectiveLocale, "network.error");
    }
    return text($effectiveLocale, "network.stopped");
  }

  function lastErrorLabel(error: PocTransportSummary["lastError"]): string {
    if (error === "acceptFailed") return text($effectiveLocale, "network.acceptFailed");
    if (error === "handshakeFailed") return text($effectiveLocale, "network.handshakeFailed");
    return text($effectiveLocale, "network.lastErrorGeneric");
  }
</script>

<section class="poc-connect-card" aria-labelledby="network-diagnostics-title">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">{text($effectiveLocale, "network.eyebrow")}</span>
      <h2 id="network-diagnostics-title">{text($effectiveLocale, "network.title")}</h2>
    </div>
    <button class="text-button" type="button" disabled={refreshing} on:click={refresh}>
      {text($effectiveLocale, refreshing ? "common.refreshing" : "common.refresh")}
    </button>
  </div>

  <p>{text($effectiveLocale, "network.transportSummary", {
    state: stateLabel(transport.state),
    port: transport.port > 0 ? transport.port : text($effectiveLocale, "common.unassigned"),
    mdns: text($effectiveLocale, transport.discoveryPublished ? "network.published" : "network.unpublished"),
    count: transport.connectedPeers
  })}</p>

  {#if transport.networkAddresses.length > 0}
    <div class="history-list" aria-label={text($effectiveLocale, "network.addresses")}>
      {#each transport.networkAddresses.slice(0, 5) as item (`${item.interfaceName}-${item.address}`)}
        <article class="history-item">
          <div class="history-item-copy">
            <div>
              <strong>{item.address}</strong>
              <p>{item.interfaceName} · {text($effectiveLocale, item.isTunnel ? "network.tunnel" : "network.normalAdapter")}</p>
            </div>
          </div>
        </article>
      {/each}
    </div>
  {:else}
    <p>{text($effectiveLocale, "network.noIpv4")}</p>
  {/if}

  <div class="history-list" aria-label={text($effectiveLocale, "network.mdnsResults")}>
    {#if transport.discoveredServices.length > 0}
      {#each transport.discoveredServices.slice(0, 5) as service (service.instanceId)}
        <article class="history-item">
          <div class="history-item-copy">
            <div>
              <strong>{service.addresses[0]}:{service.port}</strong>
              <p>{text($effectiveLocale, "network.serviceMeta", {
                version: service.protocolVersion,
                device: service.deviceId.slice(0, 8),
                capabilities: service.capabilities.join(" / ")
              })}</p>
            </div>
          </div>
        </article>
      {/each}
    {:else}
      <article class="history-item">
        <strong>{text($effectiveLocale, "network.noService")}</strong>
        <p>{text($effectiveLocale, "network.noServiceHint")}</p>
      </article>
    {/if}
  </div>

  {#if transport.lastError}
    <p class="poc-diagnostics">{lastErrorLabel(transport.lastError)}</p>
  {/if}
</section>
