<script lang="ts">
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
      return "运行中";
    }
    if (state === "failed") {
      return "异常";
    }
    return "未启动";
  }
</script>

<section class="poc-connect-card" aria-labelledby="network-diagnostics-title">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">局域网诊断</span>
      <h2 id="network-diagnostics-title">发现与监听状态</h2>
    </div>
    <button class="text-button" type="button" disabled={refreshing} on:click={refresh}>
      {refreshing ? "刷新中" : "刷新"}
    </button>
  </div>

  <p>
    WebSocket：{stateLabel(transport.state)} · 端口：{transport.port > 0 ? transport.port : "未分配"}
    · mDNS：{transport.discoveryPublished ? "已发布" : "未发布"}
    · POC 连接：{transport.connectedPeers}
  </p>

  {#if transport.networkAddresses.length > 0}
    <div class="history-list" aria-label="本机候选 IPv4 地址">
      {#each transport.networkAddresses.slice(0, 5) as item (`${item.interfaceName}-${item.address}`)}
        <article class="history-item">
          <div class="history-item-copy">
            <div>
              <strong>{item.address}</strong>
              <p>{item.interfaceName}{item.isTunnel ? " · 隧道/TUN" : " · 普通网卡"}</p>
            </div>
          </div>
        </article>
      {/each}
    </div>
  {:else}
    <p>未发现可用 IPv4。请检查 Wi‑Fi、VPN/TUN、虚拟网卡、Windows 防火墙或 AP 隔离。</p>
  {/if}

  <div class="history-list" aria-label="mDNS 浏览结果">
    {#if transport.discoveredServices.length > 0}
      {#each transport.discoveredServices.slice(0, 5) as service (service.instanceId)}
        <article class="history-item">
          <div class="history-item-copy">
            <div>
              <strong>{service.addresses[0]}:{service.port}</strong>
              <p>协议 v{service.protocolVersion} · 设备 {service.deviceId.slice(0, 8)} · {service.capabilities.join(" / ")}</p>
            </div>
          </div>
        </article>
      {/each}
    {:else}
      <article class="history-item">
        <strong>未发现其他 EggClip 服务</strong>
        <p>点击刷新可查看正式 mDNS 浏览结果；可信设备仍会使用最近成功地址回退。</p>
      </article>
    {/if}
  </div>

  {#if transport.lastError}
    <p class="poc-diagnostics">最近错误：{transport.lastError}</p>
  {/if}
</section>
