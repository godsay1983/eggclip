<script lang="ts">
  import type { HistorySummary } from "$lib/types/shell";

  export let history: HistorySummary = { used: 0, limit: 50, items: [] };
  export let onClear: () => Promise<void> | void = () => {};
  let clearing = false;

  async function clearHistory() {
    clearing = true;
    try {
      await onClear();
    } finally {
      clearing = false;
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
          <div>
            <strong>{item.title}</strong>
            <p>{item.preview}</p>
          </div>
          <span class="metadata">{item.source} · {item.receivedAt}</span>
        </article>
      {/each}
    </div>
  {:else}
    <div class="empty-state">
      <span aria-hidden="true">↔</span>
      <strong>复制后，内容会出现在这里</strong>
      <p>默认最多保存 50 条，最长保留 7 天；清空历史不会修改当前系统剪贴板。</p>
    </div>
  {/if}
</section>
