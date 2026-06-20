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
    {#each devices as device (device.id)}
      <span class="device-chip">
        <StatusDot state={device.state} />
        {device.name}
      </span>
    {/each}
  </div>
</section>
