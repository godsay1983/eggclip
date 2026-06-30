<script lang="ts">
  import type { ClipboardPreview, OutboundSyncStatus } from "$lib/types/shell";

  export let current: ClipboardPreview | null = null;
  export let outbound: OutboundSyncStatus = {
    state: "idle",
    title: "等待本机文本",
    description: "读取或监听到本机剪贴板后，会先进入本机历史，再由用户触发发送。",
    updatedAt: "",
  };
  export let onRead: () => void = () => {};
  export let onCopy: () => void = () => {};
  export let onSendPoc: () => void = () => {};
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
      完成配对后，在线实时内容会自动写入桌面剪贴板；离线补齐的历史只会显示在列表中。
    </p>
  {/if}

  <div class={`outbound-status ${outbound.state}`} aria-label="发送状态">
    <div>
      <strong>{outbound.title}</strong>
      <p>{outbound.description}</p>
      {#if outbound.updatedAt}
        <span class="metadata">更新时间：{outbound.updatedAt}</span>
      {/if}
    </div>
    <span class="outbound-badge">{outboundLabel}</span>
  </div>

  <div class="action-row">
    <button class="secondary-action" type="button" on:click={onRead}>读取本机剪贴板</button>
    <button class="primary-action" type="button" disabled={!current?.canCopy} on:click={onCopy}>
      复制此内容
    </button>
    <button
      class="secondary-action"
      type="button"
      disabled={!current || sendDisabled}
      on:click={onSendPoc}
    >
      {sendLabel}
    </button>
  </div>
</section>
