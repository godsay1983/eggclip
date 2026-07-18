<script lang="ts">
  import type { ClipboardPreview, OutboundSyncStatus } from "$lib/types/shell";
  import { effectiveLocale, formatUiMessage, uiMessage } from "$lib/i18n";

  export let current: ClipboardPreview | null = null;
  export let outbound: OutboundSyncStatus = {
    state: "idle",
    title: uiMessage("clipboard.waitingTitle"),
    description: uiMessage("clipboard.waitingDescription"),
    updatedAt: "",
  };
  export let onRead: () => void = () => {};
  export let onCopy: () => void = () => {};
  export let onSend: () => void = () => {};
  export let sendDisabled = false;
  export let sendLabel = "发送到 Harmony";

  let expanded = false;
  let currentId = "";

  $: if ((current?.id ?? "") !== currentId) {
    currentId = current?.id ?? "";
    expanded = false;
  }

  $: isLongText = (current?.text.length ?? 0) > 180;
  $: visibleText = current && expanded ? current.text : current?.preview;
  $: outboundLabel =
    outbound.state === "sent"
      ? "已发送"
      : outbound.state === "pending"
        ? "发送中"
        : outbound.state === "waiting"
          ? "待连接"
          : outbound.state === "failed"
            ? "失败"
            : outbound.state === "paused"
              ? "已暂停"
              : outbound.state === "local"
                ? "本机"
                : "空闲";
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
      复制一段文本即可开始同步；收到的实时文本会显示在这里。
    </p>
  {/if}

  {#if current || outbound.state !== "idle"}
    <div class={`outbound-status ${outbound.state}`} aria-label="发送状态">
      <div>
        <strong>{formatUiMessage($effectiveLocale, outbound.title)}</strong>
        <p>{formatUiMessage($effectiveLocale, outbound.description)}</p>
        {#if outbound.updatedAt}
          <span class="metadata">更新时间：{outbound.updatedAt}</span>
        {/if}
      </div>
      <span class="outbound-badge">{outboundLabel}</span>
    </div>
  {/if}

  <div class="action-row">
    <button class="secondary-action" type="button" on:click={onRead}>读取本机剪贴板</button>
    {#if current}
      <button class="primary-action" type="button" disabled={!current.canCopy} on:click={onCopy}>
        复制
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
