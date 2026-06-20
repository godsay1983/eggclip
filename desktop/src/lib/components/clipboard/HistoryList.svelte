<script lang="ts">
  import type { HistorySummary } from "$lib/types/shell";

  export let history: HistorySummary = { used: 0, limit: 50 };
</script>

<section class="history-section">
  <div class="section-heading compact">
    <h2>最近记录</h2>
    <span class="metadata">{history.used} / {history.limit}</span>
  </div>
  <div class="empty-state">
    <span aria-hidden="true">↔</span>
    <strong>复制后，内容会出现在这里</strong>
    <p>默认最多保存 50 条，最长保留 7 天。</p>
  </div>
</section>
