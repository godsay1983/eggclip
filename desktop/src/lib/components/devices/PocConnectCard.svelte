<script lang="ts">
  import { shellSnapshot } from "$lib/stores/shell";
  import { effectiveLocale, formatTime, text } from "$lib/i18n";
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
        return text($effectiveLocale, "poc.frameTooLarge");
      case "invalidMessage":
        return text($effectiveLocale, "poc.invalidMessage");
      case "emptyText":
        return text($effectiveLocale, "poc.emptyText");
      case "textTooLarge":
        return text($effectiveLocale, "poc.textTooLarge");
      case "binaryUnsupported":
        return text($effectiveLocale, "poc.binaryUnsupported");
      case "authenticatedFrameRejected":
        return text($effectiveLocale, "poc.authenticatedRejected");
      case "pairingClientHelloRejected":
        return text($effectiveLocale, "poc.clientHelloRejected");
      case "pairingInvitationMissing":
        return text($effectiveLocale, "poc.invitationMissing");
      case "pairingInvitationExpired":
        return text($effectiveLocale, "poc.invitationExpired");
      case "pairingInvitationConsumed":
        return text($effectiveLocale, "poc.invitationConsumed");
      case "pairingAuthProofRejected":
        return text($effectiveLocale, "poc.authProofRejected");
      case "pairingAuthSignatureRejected":
        return text($effectiveLocale, "poc.signatureRejected");
      case "pairingServerStateMissing":
        return text($effectiveLocale, "poc.stateMissing");
      case "pairingInternalError":
        return text($effectiveLocale, "poc.internalError");
      default:
        return text($effectiveLocale, "common.none");
    }
  }
</script>

<section class="poc-connect-card" aria-labelledby="poc-connect-title">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">{text($effectiveLocale, "poc.manual")}</span>
      <h2 id="poc-connect-title">{text($effectiveLocale, "poc.connectTitle")}</h2>
    </div>
  </div>
  <div class="endpoint-row">
    <label>
      <span>{text($effectiveLocale, "poc.ipv4")}</span>
      <input bind:value={host} inputmode="decimal" autocomplete="off" />
    </label>
    <label>
      <span>{text($effectiveLocale, "poc.port")}</span>
      <input bind:value={port} inputmode="numeric" placeholder={text($effectiveLocale, "poc.portExample")} autocomplete="off" />
    </label>
  </div>
  <p>{text($effectiveLocale, "poc.hint")}</p>
  {#if $shellSnapshot.lastPocEndpoint}
    <div class="recent-endpoint">
      <div>
        <strong>{text($effectiveLocale, "poc.recent")}</strong>
        <p>
          {$shellSnapshot.lastPocEndpoint.label} · {formatTime($shellSnapshot.lastPocEndpoint.connectedAtMs, $effectiveLocale)}
          · {text($effectiveLocale, "poc.recentHint")}
        </p>
      </div>
      <button
        class="text-button"
        type="button"
        disabled={busy}
        onclick={connectRecent}
      >
        {text($effectiveLocale, "poc.fillConnect")}
      </button>
    </div>
  {/if}
  <p class="poc-diagnostics">{text($effectiveLocale, "poc.diagnostics", {
    received: $shellSnapshot.pocDiagnostics.receivedFrames,
    accepted: $shellSnapshot.pocDiagnostics.acceptedItems,
    rejected: $shellSnapshot.pocDiagnostics.rejectedFrames,
    reason: rejectionLabel($shellSnapshot.pocDiagnostics.lastRejection)
  })}</p>
  <div class="poc-action-row">
    <button class="secondary-action" type="button" disabled={busy} onclick={disconnect}>{text($effectiveLocale, "poc.disconnect")}</button>
    <button class="primary-action" type="button" disabled={busy || !hasValidPort()} onclick={connect}>{text($effectiveLocale, "poc.connect")}</button>
  </div>
</section>
