<script lang="ts">
  import type { HistorySummary } from "$lib/types/shell";

  export let history: HistorySummary = { used: 0, limit: 50, items: [] };
  export let historyEnabled = true;
  export let onClear: () => Promise<void> | void = () => {};
  export let onDelete: (itemId: string) => Promise<void> | void = () => {};
  let clearing = false;
  let deletingItemId: string | null = null;

  async function clearHistory() {
    clearing = true;
    try {
      await onClear();
    } finally {
      clearing = false;
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
              <p>{item.preview}</p>
            </div>
            <button
              class="text-button danger"
              type="button"
              disabled={deletingItemId === item.id}
              on:click={() => deleteItem(item.id)}
            >
              {deletingItemId === item.id ? "删除中" : "删除"}
            </button>
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
          ? "点击“读取本机剪贴板”或接收桌面实时文本后，会在这里显示最近记录的元数据；正文预览等待加密/解密链路接入。"
          : "当前只同步实时剪贴板，不写入本机历史。可以在设置中重新开启保存历史。"}
      </p>
      <p class="empty-state-note">
        清空或关闭历史不会修改当前系统剪贴板，也不影响后续手动复制。
      </p>
    </div>
  {/if}
</section>
