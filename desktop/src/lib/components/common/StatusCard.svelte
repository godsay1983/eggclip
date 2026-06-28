<script lang="ts">
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import type { ConnectionState } from "$lib/types/shell";

  export let state: ConnectionState = "offline";
  export let title = "等待配对设备";
  export let description = "桌面端将在局域网中自动发现可信设备";
</script>

<section class="status-card" aria-label="连接状态">
  <div class="status-icon">
    <StatusDot {state} />
  </div>
  <div class="status-copy">
    <strong>{title}</strong>
    <p>{description}</p>
  </div>
  <span class:online={state === "online"} class="status-label">
    {state === "online" ? "在线" : state === "connecting" ? "连接中" : state === "paused" ? "已暂停" : "离线"}
  </span>
</section>
