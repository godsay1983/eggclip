<script lang="ts">
  import { shellSnapshot } from "$lib/stores/shell";
  import type { PocRejectionReason } from "$lib/types/shell";

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

  async function connectRecent(): Promise<void> {
    const endpoint = $shellSnapshot.lastPocEndpoint;
    if (!endpoint) {
      return;
    }
    host = endpoint.host;
    port = String(endpoint.port);
    await connect();
  }

  async function disconnect(): Promise<void> {
    busy = true;
    try {
      await shellSnapshot.disconnectAllPocPeers();
    } finally {
      busy = false;
    }
  }

  function rejectionLabel(reason: PocRejectionReason | null): string {
    switch (reason) {
      case "frameTooLarge":
        return "帧超限";
      case "invalidMessage":
        return "消息无效";
      case "emptyText":
        return "文本为空";
      case "textTooLarge":
        return "正文超限";
      case "binaryUnsupported":
        return "不支持二进制";
      case "authenticatedFrameRejected":
        return "已认证帧被拒绝";
      case "pairingClientHelloRejected":
        return "配对邀请不匹配";
      case "pairingInvitationMissing":
        return "配对邀请不存在";
      case "pairingInvitationExpired":
        return "配对邀请已过期";
      case "pairingInvitationConsumed":
        return "配对邀请已使用";
      case "pairingAuthProofRejected":
        return "配对认证无效";
      case "pairingAuthSignatureRejected":
        return "配对签名无效";
      case "pairingServerStateMissing":
        return "配对状态丢失";
      case "pairingInternalError":
        return "配对内部错误";
      default:
        return "无";
    }
  }
</script>

<section class="poc-connect-card" aria-labelledby="poc-connect-title">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">手动连接</span>
      <h2 id="poc-connect-title">连接局域网设备</h2>
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
  <p>自动发现不可用时，可输入另一台设备显示的 IPv4 和端口。候选地址不代表设备已经可信。</p>
  {#if $shellSnapshot.lastPocEndpoint}
    <div class="recent-endpoint">
      <div>
        <strong>最近成功地址</strong>
        <p>
          {$shellSnapshot.lastPocEndpoint.label} · {$shellSnapshot.lastPocEndpoint.connectedAt}
          · 仅代表 POC 地址，不代表设备可信
        </p>
      </div>
      <button
        class="text-button"
        type="button"
        disabled={busy}
        onclick={connectRecent}
      >
        回填并连接
      </button>
    </div>
  {/if}
  <p class="poc-diagnostics">
    帧诊断：接收 {$shellSnapshot.pocDiagnostics.receivedFrames} · 接受
    {$shellSnapshot.pocDiagnostics.acceptedItems} · 拒绝 {$shellSnapshot.pocDiagnostics.rejectedFrames} ·
    上次拒绝 {rejectionLabel($shellSnapshot.pocDiagnostics.lastRejection)}
  </p>
  <div class="poc-action-row">
    <button class="secondary-action" type="button" disabled={busy} onclick={disconnect}>断开连接</button>
    <button class="primary-action" type="button" disabled={busy || !hasValidPort()} onclick={connect}>连接</button>
  </div>
</section>
