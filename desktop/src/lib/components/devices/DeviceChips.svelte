<script lang="ts">
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import type { DeviceSummary } from "$lib/types/shell";

  export let devices: DeviceSummary[] = [];

  function statusLabel(state: DeviceSummary["state"]) {
    if (state === "online") {
      return "在线";
    }
    if (state === "connecting") {
      return "连接中";
    }
    if (state === "authFailed") {
      return "认证失败";
    }
    if (state === "paused") {
      return "已暂停";
    }
    return "离线";
  }

  function trustLabel(kind: DeviceSummary["trustKind"]) {
    if (kind === "trusted") {
      return "可信设备";
    }
    if (kind === "poc") {
      return "实验连接";
    }
    return "待配对";
  }
</script>

<section class="device-section">
  <div class="section-heading compact">
    <div>
      <h2>设备</h2>
      <span class="metadata">POC 连接不等于可信设备</span>
    </div>
    <button class="text-button" type="button" disabled title="配对流程接入后开放">添加设备</button>
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
        <article
          class:online={device.state === "online"}
          class:connecting={device.state === "connecting"}
          class:auth-failed={device.state === "authFailed"}
          class:paused={device.state === "paused"}
          class:poc-device={device.trustKind === "poc"}
          class:placeholder-device={device.trustKind === "placeholder"}
          class="device-card"
          title={`${device.name}：${statusLabel(device.state)}`}
        >
          <div class="device-card-header">
            <StatusDot state={device.state} />
            <div>
              <strong>{device.name}</strong>
              <p>{trustLabel(device.trustKind)} · {statusLabel(device.state)}</p>
            </div>
          </div>
          <dl class="device-meta-grid">
            <div>
              <dt>短指纹</dt>
              <dd>{device.shortFingerprint}</dd>
            </div>
            <div>
              <dt>最后在线</dt>
              <dd>{device.lastSeen}</dd>
            </div>
            {#if device.endpoint}
              <div>
                <dt>端点</dt>
                <dd>{device.endpoint}</dd>
              </div>
            {/if}
          </dl>
          <p class="device-note">{device.note}</p>
        </article>
      {/each}
    {/if}
  </div>
</section>
