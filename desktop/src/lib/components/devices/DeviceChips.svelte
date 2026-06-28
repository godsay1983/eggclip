<script lang="ts">
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import type { DeviceSummary } from "$lib/types/shell";

  export let devices: DeviceSummary[] = [];
</script>

<section class="device-section">
  <div class="section-heading compact">
    <h2>设备</h2>
    <button class="text-button" type="button">添加设备</button>
  </div>
  <div class="device-list">
    {#if devices.length === 0}
      <div class="device-empty">
        <span aria-hidden="true">备</span>
        <div>
          <strong>暂无可信设备</strong>
          <p>正式配对完成后，这里会显示设备状态和最后在线时间。</p>
        </div>
      </div>
    {:else}
      {#each devices as device (device.id)}
        <span class="device-chip">
          <StatusDot state={device.state} />
          {device.name}
        </span>
      {/each}
    {/if}
  </div>
</section>
