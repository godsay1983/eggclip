<script lang="ts">
  import type { HistorySummary } from "$lib/types/shell";

  export let history: HistorySummary = { used: 0, limit: 50, items: [] };
  export let historyEnabled = true;
  export let onClear: () => Promise<void> | void = () => {};
  export let onDelete: (itemId: string) => Promise<void> | void = () => {};
  export let onCopy: (itemId: string) => Promise<boolean> | boolean = () => false;
  let clearing = false;
  let deletingItemId: string | null = null;
  let expandedItemId: string | null = null;
  let copiedItemId: string | null = null;

  async function clearHistory() {
    clearing = true;
    try {
      await onClear();
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
    } finally {
      deletingItemId = null;
    }
  }
</script>

<section class="history-section">
  <div class="section-heading compact">
    <div>
      <h2>最近记录</h2>
      <span class="metadata">{history.used} / {history.limit}</span>
    </div>
    <button
      class="text-button danger"
      type="button"
      disabled={clearing}
      on:click={clearHistory}
    >
      {clearing ? "清理中" : "清空历史"}
    </button>
  </div>
  {#if history.items.length > 0}
    <div class="history-list" aria-label="最近历史记录">
      {#each history.items as item (item.id)}
        <article class="history-item">
          <div class="history-item-copy">
            <div>
              <strong>{item.title}</strong>
              <p>{expandedItemId === item.id && item.text ? item.text : item.preview}</p>
            </div>
            <div class="history-item-actions">
              {#if item.text && item.text !== item.preview}
                <button class="text-button" type="button" on:click={() => {
                  expandedItemId = expandedItemId === item.id ? null : item.id;
                }}>{expandedItemId === item.id ? "收起" : "详情"}</button>
              {/if}
              <button class="text-button" type="button" disabled={!item.canCopy}
                on:click={() => copyItem(item.id)}>{copiedItemId === item.id ? "已复制" : "复制"}</button>
              <button
                class="text-button danger"
                type="button"
                disabled={deletingItemId === item.id}
                on:click={() => deleteItem(item.id)}
              >
                {deletingItemId === item.id ? "删除中" : "删除"}
              </button>
            </div>
          </div>
          <span class="metadata">{item.source} · {item.receivedAt}</span>
        </article>
      {/each}
    </div>
  {:else}
    <div class="empty-state">
      <span aria-hidden="true">{historyEnabled ? "↔" : "·"}</span>
      <strong>{historyEnabled ? "还没有本机历史" : "历史保存已关闭"}</strong>
      <p>
        {historyEnabled
          ? "复制或收到文本后会显示在这里。"
          : "当前只同步实时内容，可在设置中重新开启历史。"}
      </p>
    </div>
  {/if}
</section>
