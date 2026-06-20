<script lang="ts">
  import type { ClipboardPreview } from "$lib/types/shell";

  export let current: ClipboardPreview | null = null;
</script>

<section class="clipboard-card">
  <div class="section-heading">
    <div>
      <span class="eyebrow">当前剪贴板</span>
      <h2>{current?.title ?? "暂无同步内容"}</h2>
    </div>
    <span class="metadata">仅纯文本</span>
  </div>

  {#if current}
    <p class="clipboard-placeholder">{current.preview}</p>
    <p class="metadata">来源：{current.source} · {current.receivedAt}</p>
  {:else}
    <p class="clipboard-placeholder">
      完成配对后，在线实时内容会自动写入桌面剪贴板；离线补齐的历史只会显示在列表中。
    </p>
  {/if}

  <button class="primary-action" type="button" disabled={!current?.canCopy}>复制此内容</button>
</section>
