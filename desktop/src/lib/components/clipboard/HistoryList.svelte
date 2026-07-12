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
      <h2>最近记录</h2>
      <span class="metadata">{history.used} / {history.limit}</span>
    </div>
    <button
      class="text-button danger"
      type="button"
      disabled={clearing || history.items.length === 0}
      on:click={() => (clearConfirmationVisible = true)}
    >
      {clearing ? "清理中" : "清空历史"}
    </button>
  </div>
  {#if clearConfirmationVisible}
    <div class="history-confirmation" role="alert">
      <span>清空全部本机历史？</span>
      <div>
        <button class="text-button danger" type="button" disabled={clearing} on:click={clearHistory}>
          {clearing ? "清理中" : "确认清空"}
        </button>
        <button class="text-button" type="button" disabled={clearing} on:click={() => (clearConfirmationVisible = false)}>取消</button>
      </div>
    </div>
  {/if}
  {#if history.items.length > 0}
    <div class="history-list" aria-label="最近历史记录">
      {#each history.items as item (item.id)}
        <article class="history-item" class:expanded={actionsItemId === item.id}>
          <div class="history-item-row">
            <button
              class="history-item-main"
              type="button"
              disabled={!item.canCopy}
              aria-label={`复制 ${item.title}`}
              on:click={() => copyItem(item.id)}
            >
              <span class="history-item-heading">
                <strong>{item.title}</strong>
                <span>{copiedItemId === item.id ? "已复制" : item.receivedAt}</span>
              </span>
              <span class="history-item-preview">
                {expandedItemId === item.id && item.text ? item.text : item.preview}
              </span>
            </button>
            <button
              class="history-more"
              type="button"
              aria-label={`${item.title}更多操作`}
              aria-expanded={actionsItemId === item.id}
              on:click={() => {
                actionsItemId = actionsItemId === item.id ? null : item.id;
                pendingDeleteItemId = null;
              }}
            >•••</button>
          </div>
          {#if actionsItemId === item.id}
            <div class="history-item-actions">
              <span class="metadata">{item.source}</span>
              {#if item.text && item.text !== item.preview}
                <button class="text-button" type="button" on:click={() => {
                  expandedItemId = expandedItemId === item.id ? null : item.id;
                }}>{expandedItemId === item.id ? "收起详情" : "查看详情"}</button>
              {/if}
              <button
                class="text-button danger"
                type="button"
                disabled={deletingItemId === item.id}
                on:click={() => (pendingDeleteItemId = item.id)}
              >删除</button>
            </div>
          {/if}
          {#if pendingDeleteItemId === item.id}
            <div class="history-confirmation" role="alert">
              <span>删除这条记录？</span>
              <div>
                <button class="text-button danger" type="button" disabled={deletingItemId === item.id} on:click={() => deleteItem(item.id)}>
                  {deletingItemId === item.id ? "删除中" : "确认删除"}
                </button>
                <button class="text-button" type="button" disabled={deletingItemId === item.id} on:click={() => (pendingDeleteItemId = null)}>取消</button>
              </div>
            </div>
          {/if}
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
