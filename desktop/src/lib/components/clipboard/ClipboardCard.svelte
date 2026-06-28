<script lang="ts">
  import type { ClipboardPreview } from "$lib/types/shell";

  export let current: ClipboardPreview | null = null;
  export let onRead: () => void = () => {};
  export let onCopy: () => void = () => {};
  export let onSendPoc: () => void = () => {};

  let expanded = false;
  let currentId = "";

  $: if ((current?.id ?? "") !== currentId) {
    currentId = current?.id ?? "";
    expanded = false;
  }

  $: isLongText = (current?.text.length ?? 0) > 180;
  $: visibleText = current && expanded ? current.text : current?.preview;
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
    <p class="clipboard-placeholder" class:expanded>{visibleText}</p>
    <div class="clipboard-meta-row">
      <p class="metadata">
        来源：{current.source} · {current.receivedAt} · {current.text.length} 字符
      </p>
      {#if isLongText}
        <button
          class="text-button"
          type="button"
          aria-expanded={expanded}
          on:click={() => {
            expanded = !expanded;
          }}>{expanded ? "收起" : "展开"}</button
        >
      {/if}
    </div>
  {:else}
    <p class="clipboard-placeholder">
      完成配对后，在线实时内容会自动写入桌面剪贴板；离线补齐的历史只会显示在列表中。
    </p>
  {/if}

  <div class="action-row">
    <button class="secondary-action" type="button" on:click={onRead}>读取本机剪贴板</button>
    <button class="primary-action" type="button" disabled={!current?.canCopy} on:click={onCopy}>
      复制此内容
    </button>
    <button class="secondary-action" type="button" disabled={!current} on:click={onSendPoc}>
      发送到 Harmony
    </button>
  </div>
</section>
