<script lang="ts">
  import { shellSnapshot } from "$lib/stores/shell";

  let host = "127.0.0.1";
  let port = "";
  let busy = false;

  function hasValidPort(): boolean {
    const parsedPort = Number(port);
    return Number.isInteger(parsedPort) && parsedPort >= 1 && parsedPort <= 65535;
  }

  async function connect(): Promise<void> {
    const parsedPort = Number(port);
    if (!hasValidPort()) {
      return;
    }
    busy = true;
    try {
      await shellSnapshot.connectPocPeer(host, parsedPort);
    } catch (_) {
      // The store exposes a user-facing error in the status card.
    } finally {
      busy = false;
    }
  }

  async function disconnect(): Promise<void> {
    busy = true;
    try {
      await shellSnapshot.disconnectAllPocPeers();
    } finally {
      busy = false;
    }
  }
</script>

<section class="poc-connect-card" aria-labelledby="poc-connect-title">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">D1 手动互通</span>
      <h2 id="poc-connect-title">连接另一桌面 POC</h2>
    </div>
  </div>
  <div class="endpoint-row">
    <label>
      <span>IPv4 地址</span>
      <input bind:value={host} inputmode="decimal" autocomplete="off" />
    </label>
    <label>
      <span>端口</span>
      <input bind:value={port} inputmode="numeric" placeholder="例如 43210" autocomplete="off" />
    </label>
  </div>
  <p>在另一实例状态卡中查看候选 IPv4 和 WebSocket POC 端口。</p>
  <div class="poc-action-row">
    <button class="secondary-action" type="button" disabled={busy} onclick={disconnect}>断开全部</button>
    <button class="primary-action" type="button" disabled={busy || !hasValidPort()} onclick={connect}>连接</button>
  </div>
</section>
