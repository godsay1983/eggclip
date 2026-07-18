<script lang="ts">
  import type { ClipboardPreview, OutboundSyncStatus } from "$lib/types/shell";
  import { effectiveLocale, formatTime, formatUiMessage, text, uiMessage } from "$lib/i18n";

  export let current: ClipboardPreview | null = null;
  export let outbound: OutboundSyncStatus = {
    state: "idle",
    title: uiMessage("clipboard.waitingTitle"),
    description: uiMessage("clipboard.waitingDescription"),
    updatedAtMs: null,
  };
  export let onRead: () => void = () => {};
  export let onCopy: () => void = () => {};
  export let onSend: () => void = () => {};
  export let sendDisabled = false;
  export let sendLabel = "";

  let expanded = false;
  let currentId = "";

  $: if ((current?.id ?? "") !== currentId) {
    currentId = current?.id ?? "";
    expanded = false;
  }

  $: isLongText = (current?.text.length ?? 0) > 180;
  $: visibleText = current && expanded ? current.text : current?.preview;
  $: sourceLabel = current?.sourceKind === "local"
    ? text($effectiveLocale, "clipboard.sourceLocal")
    : current?.sourceKind === "localMonitor"
      ? text($effectiveLocale, "clipboard.sourceLocalMonitor")
      : current?.sourceKind === "poc"
        ? text($effectiveLocale, "clipboard.sourcePoc", { device: current.sourceDevice ?? "—" })
        : text($effectiveLocale, "clipboard.sourceTrusted", { device: current?.sourceDevice ?? "—" });
  $: outboundLabel =
    outbound.state === "sent"
      ? text($effectiveLocale, "outbound.sent")
      : outbound.state === "pending"
        ? text($effectiveLocale, "outbound.sending")
        : outbound.state === "waiting"
          ? text($effectiveLocale, "outbound.waiting")
          : outbound.state === "failed"
            ? text($effectiveLocale, "outbound.failed")
            : outbound.state === "paused"
              ? text($effectiveLocale, "outbound.paused")
              : outbound.state === "local"
                ? text($effectiveLocale, "outbound.local")
                : text($effectiveLocale, "outbound.idle");
</script>

<section class="clipboard-card">
  <div class="section-heading">
    <div>
      <span class="eyebrow">{text($effectiveLocale, "clipboard.current")}</span>
      <h2>{current ? text($effectiveLocale, "clipboard.textBytes", { count: current.byteLength }) : text($effectiveLocale, "clipboard.emptyTitle")}</h2>
    </div>
    <span class="metadata">{text($effectiveLocale, "clipboard.plainText")}</span>
  </div>

  {#if current}
    <p class="clipboard-placeholder" class:expanded>{visibleText}</p>
    <div class="clipboard-meta-row">
      <p class="metadata">
        {text($effectiveLocale, "clipboard.meta", { source: sourceLabel, time: formatTime(current.receivedAtMs, $effectiveLocale), count: current.text.length })}
      </p>
      {#if isLongText}
        <button
          class="text-button"
          type="button"
          aria-expanded={expanded}
          on:click={() => {
            expanded = !expanded;
          }}>{text($effectiveLocale, expanded ? "clipboard.collapse" : "clipboard.expand")}</button
        >
      {/if}
    </div>
  {:else}
    <p class="clipboard-placeholder">
      {text($effectiveLocale, "clipboard.emptyHint")}
    </p>
  {/if}

  {#if current || outbound.state !== "idle"}
    <div class={`outbound-status ${outbound.state}`} aria-label={text($effectiveLocale, "clipboard.sendStatus")}>
      <div>
        <strong>{formatUiMessage($effectiveLocale, outbound.title)}</strong>
        <p>{formatUiMessage($effectiveLocale, outbound.description)}</p>
        {#if outbound.updatedAtMs !== null}
          <span class="metadata">{text($effectiveLocale, "clipboard.updatedAt", { time: formatTime(outbound.updatedAtMs, $effectiveLocale) })}</span>
        {/if}
      </div>
      <span class="outbound-badge">{outboundLabel}</span>
    </div>
  {/if}

  <div class="action-row">
    <button class="secondary-action" type="button" on:click={onRead}>{text($effectiveLocale, "clipboard.readLocal")}</button>
    {#if current}
      <button class="primary-action" type="button" disabled={!current.canCopy} on:click={onCopy}>
        {text($effectiveLocale, "common.copy")}
      </button>
      <button
        class="secondary-action"
        type="button"
        disabled={sendDisabled}
        on:click={onSend}
      >
        {sendLabel}
      </button>
    {/if}
  </div>
</section>
