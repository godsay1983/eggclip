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

  $: hasTunnelAddress = transport.networkAddresses.some((item) => item.isTunnel);
  $: hasNormalAddress = transport.networkAddresses.some((item) => !item.isTunnel);
  $: canShareEndpoint = transport.state === "running" && transport.port > 0 && hasNormalAddress;

  function primaryHint(): string {
    if (transport.state === "failed") {
      return "监听或发现启动失败。先检查 Windows 防火墙是否允许 EggClip，再重启同步监听。";
    }
    if (!hasNormalAddress && hasTunnelAddress) {
      return "当前只看到 VPN/TUN 或虚拟网卡地址。手机可能无法直连，请切回同一 Wi‑Fi 或开启 VPN TUN 后再测。";
    }
    if (!transport.discoveryPublished) {
      return "mDNS 尚未发布成功。自动发现不可用时，优先使用手动 IP 作为回退入口。";
    }
    if (canShareEndpoint) {
      return "可以在鸿蒙设备页输入下方普通网卡 IPv4 和端口，作为自动发现失败时的手动连接回退。";
    }
    return "等待 WebSocket 监听和本机 IPv4 地址就绪。";
  }

  function firstNormalAddress(): string {
    return transport.networkAddresses.find((item) => !item.isTunnel)?.address ?? "暂无普通网卡 IPv4";
  }
</script>

<section class="poc-connect-card" aria-labelledby="network-troubleshooting-title">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">网络排障</span>
      <h2 id="network-troubleshooting-title">手动连接检查</h2>
    </div>
  </div>

  <p>{primaryHint()}</p>

  <div class="history-list" aria-label="网络排障检查项">
    <article class="history-item">
      <strong>手动端点</strong>
      <p>{firstNormalAddress()} · 端口 {transport.port > 0 ? transport.port : "未分配"}</p>
    </article>
    <article class="history-item">
      <strong>防火墙</strong>
      <p>Windows 首次弹窗应允许专用网络；公用网络或访客 Wi‑Fi 可能阻止手机访问。</p>
    </article>
    <article class="history-item">
      <strong>路由器/AP 隔离</strong>
      <p>手机和电脑必须在同一局域网，且路由器未开启客户端隔离。</p>
    </article>
    <article class="history-item">
      <strong>VPN/TUN</strong>
      <p>{hasTunnelAddress ? "已检测到隧道/TUN 地址；模拟器可能依赖该链路发现桌面端。" : "未检测到隧道/TUN 地址；优先使用普通 Wi‑Fi IPv4。"}</p>
    </article>
  </div>
</section>
