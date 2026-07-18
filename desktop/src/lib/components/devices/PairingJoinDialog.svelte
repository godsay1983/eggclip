<script lang="ts">
  import {
    cancelPairingJoinAttempt,
    connectTrustedPeer,
    parsePairingJoinInvitation,
  } from "$lib/api/pairing";
  import {
    classifyPairingJoinError,
    emptyPairingJoinFormState,
    prioritizedPairingAddresses,
    readyPairingJoinFormState,
    type PairingJoinIssue,
  } from "$lib/pairing-join";
  import type { PairingJoinAttemptSummary } from "$lib/types/pairing";
  import { effectiveLocale, formatUiMessage } from "$lib/i18n";

  export let onClose: () => void = () => {};
  export let onConnected: () => Promise<void> | void = () => {};

  const initialForm = emptyPairingJoinFormState();
  let invitationText = initialForm.invitationText;
  let attempt: PairingJoinAttemptSummary | null = null;
  let selectedCandidateId = initialForm.selectedCandidateId;
  let confirmationMatches = initialForm.confirmationMatches;
  let advancedOpen = false;
  let manualHost = initialForm.manualHost;
  let manualPort = initialForm.manualPort;
  let useManualAddress = initialForm.useManualAddress;
  let state: "input" | "parsing" | "ready" | "connecting" | "success" | "error" = "input";
  let progress = "";
  let issue: PairingJoinIssue | null = null;

  function clearSensitiveState(): void {
    const cleared = emptyPairingJoinFormState();
    invitationText = cleared.invitationText;
    attempt = null;
    selectedCandidateId = cleared.selectedCandidateId;
    confirmationMatches = cleared.confirmationMatches;
    manualHost = cleared.manualHost;
    manualPort = cleared.manualPort;
    useManualAddress = cleared.useManualAddress;
  }

  async function closeDialog(): Promise<void> {
    if (state === "connecting") return;
    const attemptId = attempt?.attemptId;
    clearSensitiveState();
    if (attemptId) {
      try {
        await cancelPairingJoinAttempt(attemptId);
      } catch (_) {
        // The local secret is still bounded by the backend expiry sweep.
      }
    }
    onClose();
  }

  async function validateInvitation(): Promise<void> {
    if (invitationText.trim().length === 0) return;
    state = "parsing";
    issue = null;
    const previousAttemptId = attempt?.attemptId;
    if (previousAttemptId) {
      await cancelPairingJoinAttempt(previousAttemptId).catch(() => undefined);
    }
    try {
      attempt = await parsePairingJoinInvitation(invitationText.trim());
      const ready = readyPairingJoinFormState(attempt);
      invitationText = ready.invitationText;
      selectedCandidateId = ready.selectedCandidateId;
      confirmationMatches = ready.confirmationMatches;
      manualHost = ready.manualHost;
      manualPort = ready.manualPort;
      useManualAddress = ready.useManualAddress;
      state = "ready";
    } catch (error) {
      attempt = null;
      issue = classifyPairingJoinError(error);
      state = "error";
    }
  }

  async function connect(): Promise<void> {
    if (!attempt || !confirmationMatches) return;
    state = "connecting";
    issue = null;
    try {
      if (useManualAddress) {
        progress = `正在连接 ${manualHost.trim()}:${manualPort}`;
        await connectTrustedPeer(attempt.attemptId, {
          manualHost: manualHost.trim(),
          manualPort,
        });
      } else {
        const candidates = prioritizedPairingAddresses(attempt.addresses, selectedCandidateId);
        let lastNetworkIssue: PairingJoinIssue | null = null;
        for (let index = 0; index < candidates.length; index += 1) {
          const candidate = candidates[index];
          progress = `正在尝试地址 ${index + 1}/${candidates.length} · ${candidate.displayAddress}`;
          try {
            await connectTrustedPeer(attempt.attemptId, { candidateId: candidate.candidateId });
            lastNetworkIssue = null;
            break;
          } catch (error) {
            const candidateIssue = classifyPairingJoinError(error);
            if (!candidateIssue.retryableNetwork || index === candidates.length - 1) {
              throw error;
            }
            lastNetworkIssue = candidateIssue;
          }
        }
        if (lastNetworkIssue) issue = lastNetworkIssue;
      }
      clearSensitiveState();
      state = "success";
      progress = "已建立加密连接并保存可信设备";
      await onConnected();
    } catch (error) {
      issue = classifyPairingJoinError(error);
      if (!issue.retryableNetwork) {
        attempt = null;
        confirmationMatches = false;
      }
      state = "error";
    }
  }

  function expiryLabel(expiresAtMs: number): string {
    return new Date(expiresAtMs).toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
    });
  }
</script>

<svelte:window on:keydown={(event) => event.key === "Escape" && void closeDialog()} />

<div class="pairing-dialog-layer">
  <button class="pairing-dialog-backdrop" type="button" aria-label="取消加入设备" on:click={() => closeDialog()}></button>
  <dialog open class="pairing-dialog-card" aria-modal="true" aria-labelledby="pairing-dialog-title">
    <header class="pairing-dialog-header">
      <div class="pairing-dialog-heading">
        <span class="pairing-dialog-mark" aria-hidden="true">
          <svg viewBox="0 0 24 24" role="img">
            <rect x="2.5" y="5" width="12" height="10" rx="2.5"></rect>
            <path d="M6 19h5M8.5 15v4"></path>
            <rect x="15.5" y="8" width="6" height="9" rx="1.8"></rect>
            <path d="M17.8 14.5h1.4"></path>
          </svg>
        </span>
        <div>
          <span class="pairing-dialog-eyebrow">可信设备配对</span>
          <h2 id="pairing-dialog-title">加入另一台电脑</h2>
          <p>粘贴邀请并核对确认码，建立加密连接。</p>
        </div>
      </div>
      <button class="qr-dialog-close" type="button" aria-label="关闭" on:click={() => closeDialog()}>×</button>
    </header>

    {#if state === "input" || state === "parsing" || (state === "error" && !attempt)}
      <label class="pairing-invitation-input">
        <span>配对邀请</span>
        <textarea
          rows="4"
          maxlength="4096"
          placeholder="eggclip://pair?p=…"
          autocomplete="off"
          spellcheck="false"
          bind:value={invitationText}
          disabled={state === "parsing"}
        ></textarea>
      </label>
      <p class="pairing-privacy-note">邀请只在本次配对期间使用，校验后不会继续显示完整内容。</p>
      {#if issue}
        <div class="pairing-issue" role="alert">
          <strong>{formatUiMessage($effectiveLocale, issue.title)}</strong>
          <p>{formatUiMessage($effectiveLocale, issue.message)}</p>
        </div>
      {/if}
      <button
        class="primary-action"
        type="button"
        disabled={state === "parsing" || invitationText.trim().length === 0}
        on:click={() => validateInvitation()}
      >{state === "parsing" ? "正在校验…" : "校验邀请"}</button>
    {:else if state === "success"}
      <div class="pairing-success" role="status">
        <span aria-hidden="true">✓</span>
        <strong>配对成功</strong>
        <p>{progress}</p>
      </div>
      <button class="primary-action" type="button" on:click={() => closeDialog()}>完成</button>
    {:else if attempt}
      <section class="pairing-summary" aria-label="邀请摘要">
        <div>
          <span>邀请设备</span>
          <strong>{attempt.issuerDeviceName}</strong>
        </div>
        <div>
          <span>设备短指纹</span>
          <strong>#{attempt.issuerShortFingerprint}</strong>
        </div>
        <div>
          <span>同步空间</span>
          <strong>#{attempt.spaceShortId}</strong>
        </div>
        <div>
          <span>有效期</span>
          <strong>{expiryLabel(attempt.expiresAtMs)} 前</strong>
        </div>
      </section>

      <div class="pairing-confirmation-code">
        <span>请与另一台电脑核对确认码</span>
        <strong>{attempt.confirmationCode}</strong>
      </div>
      <label class="pairing-confirmation-check">
        <input type="checkbox" bind:checked={confirmationMatches} disabled={state === "connecting"} />
        <span>两台电脑显示的确认码一致</span>
      </label>

      {#if attempt.addresses.length > 0}
        <fieldset class="pairing-addresses" disabled={state === "connecting" || useManualAddress}>
          <legend>候选地址</legend>
          <p>默认依次尝试全部地址；选择项会优先尝试。</p>
          {#each attempt.addresses as address}
            <label>
              <input type="radio" name="pairing-address" value={address.candidateId} bind:group={selectedCandidateId} />
              <span>{address.displayAddress}</span>
            </label>
          {/each}
        </fieldset>
      {/if}

      <details class="pairing-advanced" bind:open={advancedOpen}>
        <summary>高级：手动输入地址</summary>
        <label class="pairing-manual-toggle">
          <input type="checkbox" bind:checked={useManualAddress} disabled={state === "connecting"} />
          <span>忽略邀请候选地址，使用手动地址</span>
        </label>
        {#if useManualAddress}
          <div class="pairing-manual-fields">
            <label><span>IPv4</span><input placeholder="192.168.1.10" bind:value={manualHost} /></label>
            <label><span>端口</span><input type="number" min="1" max="65535" bind:value={manualPort} /></label>
          </div>
        {/if}
      </details>

      {#if state === "connecting"}
        <p class="pairing-progress" role="status">{progress}</p>
      {/if}
      {#if issue}
        <div class="pairing-issue" role="alert">
          <strong>{formatUiMessage($effectiveLocale, issue.title)}</strong>
          <p>{formatUiMessage($effectiveLocale, issue.message)}</p>
        </div>
      {/if}
      <div class="pairing-dialog-actions">
        <button
          class="primary-action"
          type="button"
          disabled={state === "connecting" || !confirmationMatches || (useManualAddress && (manualHost.trim().length === 0 || manualPort < 1 || manualPort > 65535))}
          on:click={() => connect()}
        >{state === "connecting" ? "正在连接…" : "确认并连接"}</button>
        <button class="text-button" type="button" disabled={state === "connecting"} on:click={() => closeDialog()}>取消</button>
      </div>
    {/if}
  </dialog>
</div>
