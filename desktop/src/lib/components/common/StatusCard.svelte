<script lang="ts">
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import type { ConnectionState } from "$lib/types/shell";

  export let state: ConnectionState = "offline";
  export let title = "等待配对设备";
  export let description = "桌面端将在局域网中自动发现可信设备";
</script>

<section class="status-card" aria-label="连接状态">
  <StatusDot {state} />
  <div>
    <strong>{title}</strong>
    <p>{description}</p>
  </div>
</section>
