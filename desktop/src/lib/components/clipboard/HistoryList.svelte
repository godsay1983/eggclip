<script lang="ts">
  import { effectiveLocale, formatTime, text } from "$lib/i18n";
  import type { HistorySummary } from "$lib/types/shell";

  export let history: HistorySummary = { used: 0, limit: 50, items: [] };
  export let historyEnabled = true;
  export let onClear: () => Promise<void> | void = () => {};
  export let onDelete: (itemId: string) => Promise<void> | void = () => {};
  export let onCopy: (itemId: string) => Promise<boolean> | boolean = () => false;
  let clearing = false;
  let deletingItemId: string | null = null;
  let expandedItemId: string | null = null;
  let actionsItemId: string | null = null;
  let pendingDeleteItemId: string | null = null;
  let clearConfirmationVisible = false;
  let copiedItemId: string | null = null;

  async function clearHistory() {
    clearing = true;
    try {
      await onClear();
      clearConfirmationVisible = false;
    } finally {
      clearing = false;
    }
  }

  async function copyItem(itemId: string) {
    if (await onCopy(itemId)) {
      copiedItemId = itemId;
      window.setTimeout(() => {
        if (copiedItemId === itemId) copiedItemId = null;
      }, 1600);
    }
  }

  async function deleteItem(itemId: string) {
    deletingItemId = itemId;
    try {
      await onDelete(itemId);
      pendingDeleteItemId = null;
      actionsItemId = null;
    } finally {
      deletingItemId = null;
    }
  }
</script>

<section class="history-section">
  <div class="section-heading compact">
    <div>
      <h2>{text($effectiveLocale, "history.title")}</h2>
      <span class="metadata">{history.used} / {history.limit}</span>
    </div>
    <button
      class="text-button danger"
      type="button"
      disabled={clearing || history.items.length === 0}
      on:click={() => (clearConfirmationVisible = true)}
    >
      {text($effectiveLocale, clearing ? "history.clearing" : "history.clear")}
    </button>
  </div>
  {#if clearConfirmationVisible}
    <div class="history-confirmation" role="alert">
      <span>{text($effectiveLocale, "history.clearQuestion")}</span>
      <div>
        <button class="text-button danger" type="button" disabled={clearing} on:click={clearHistory}>
          {text($effectiveLocale, clearing ? "history.clearing" : "history.confirmClear")}
        </button>
        <button class="text-button" type="button" disabled={clearing} on:click={() => (clearConfirmationVisible = false)}>{text($effectiveLocale, "common.cancel")}</button>
      </div>
    </div>
  {/if}
  {#if history.items.length > 0}
    <div class="history-list" aria-label={text($effectiveLocale, "history.listLabel")}>
      {#each history.items as item (item.id)}
        {@const itemTitle = text($effectiveLocale, "history.textBytes", { count: item.contentLength })}
        {@const deviceLabel = item.originDeviceId.slice(0, 8) || "—"}
        <article class="history-item" class:expanded={actionsItemId === item.id}>
          <div class="history-item-row">
            <button
              class="history-item-main"
              type="button"
              disabled={!item.canCopy}
              aria-label={text($effectiveLocale, "history.copyItem", { title: itemTitle })}
              on:click={() => copyItem(item.id)}
            >
              <span class="history-item-heading">
                <strong>{itemTitle}</strong>
                <span>{copiedItemId === item.id ? text($effectiveLocale, "common.copied") : formatTime(item.receivedAtMs, $effectiveLocale)}</span>
              </span>
              <span class="history-item-preview">
                {expandedItemId === item.id && item.text ? item.text : item.preview || text($effectiveLocale, "history.contentUnavailable")}
              </span>
            </button>
            <button
              class="history-more"
              type="button"
              aria-label={text($effectiveLocale, "history.moreActions", { title: itemTitle })}
              aria-expanded={actionsItemId === item.id}
              on:click={() => {
                actionsItemId = actionsItemId === item.id ? null : item.id;
                pendingDeleteItemId = null;
              }}
            >•••</button>
          </div>
          {#if actionsItemId === item.id}
            <div class="history-item-actions">
              <span class="metadata">{text($effectiveLocale, "history.sourceDevice", { device: deviceLabel })}</span>
              {#if item.text && item.text !== item.preview}
                <button class="text-button" type="button" on:click={() => {
                  expandedItemId = expandedItemId === item.id ? null : item.id;
                }}>{text($effectiveLocale, expandedItemId === item.id ? "history.hideDetails" : "history.showDetails")}</button>
              {/if}
              <button
                class="text-button danger"
                type="button"
                disabled={deletingItemId === item.id}
                on:click={() => (pendingDeleteItemId = item.id)}
              >{text($effectiveLocale, "common.delete")}</button>
            </div>
          {/if}
          {#if pendingDeleteItemId === item.id}
            <div class="history-confirmation" role="alert">
              <span>{text($effectiveLocale, "history.deleteQuestion")}</span>
              <div>
                <button class="text-button danger" type="button" disabled={deletingItemId === item.id} on:click={() => deleteItem(item.id)}>
                  {text($effectiveLocale, deletingItemId === item.id ? "history.deleting" : "history.confirmDelete")}
                </button>
                <button class="text-button" type="button" disabled={deletingItemId === item.id} on:click={() => (pendingDeleteItemId = null)}>{text($effectiveLocale, "common.cancel")}</button>
              </div>
            </div>
          {/if}
        </article>
      {/each}
    </div>
  {:else}
    <div class="empty-state">
      <span aria-hidden="true">{historyEnabled ? "↔" : "·"}</span>
      <strong>{text($effectiveLocale, historyEnabled ? "history.empty" : "history.disabled")}</strong>
      <p>
        {historyEnabled
          ? text($effectiveLocale, "history.emptyHint")
          : text($effectiveLocale, "history.disabledHint")}
      </p>
    </div>
  {/if}
</section>
