<script lang="ts">
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import type { DeviceSummary } from "$lib/types/shell";

  export let devices: DeviceSummary[] = [];
  export let onRename: (deviceId: string, name: string) => Promise<void> | void = () => {};
  export let onRemove: (deviceId: string) => Promise<unknown> | unknown = () => {};
  export let canRemove: (device: DeviceSummary) => boolean = () => true;

  let editingDeviceId = "";
  let editingName = "";
  let busyDeviceId = "";
  let pendingRemovalDeviceId = "";

  async function saveName(device: DeviceSummary): Promise<void> {
    const normalized = editingName.trim();
    if (normalized.length === 0 || normalized.length > 32) return;
    busyDeviceId = device.id;
    try {
      await onRename(device.id, normalized);
      editingDeviceId = "";
    } finally {
      busyDeviceId = "";
    }
  }

  async function removeDevice(device: DeviceSummary): Promise<void> {
    busyDeviceId = device.id;
    try {
      await onRemove(device.id);
      pendingRemovalDeviceId = "";
    } finally {
      busyDeviceId = "";
    }
  }

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
      <span class="metadata">已配对设备会在连接后显示在线状态</span>
    </div>
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
          {#if device.trustKind === "trusted"}
            <div class="device-management-actions">
              {#if editingDeviceId === device.id}
                <input
                  aria-label="可信设备名称"
                  maxlength="32"
                  bind:value={editingName}
                  disabled={busyDeviceId === device.id}
                />
                <button
                  class="text-button"
                  type="button"
                  disabled={busyDeviceId === device.id || editingName.trim().length === 0}
                  on:click={() => saveName(device)}
                >保存</button>
                <button class="text-button" type="button" on:click={() => (editingDeviceId = "")}>取消</button>
              {:else}
                <button
                  class="text-button"
                  type="button"
                  disabled={busyDeviceId === device.id}
                  on:click={() => {
                    editingDeviceId = device.id;
                    editingName = device.name;
                  }}
                >重命名</button>
                {#if canRemove(device)}
                  <button
                    class="text-button danger-action"
                    type="button"
                    disabled={busyDeviceId === device.id}
                    on:click={() => (pendingRemovalDeviceId = device.id)}
                  >{busyDeviceId === device.id ? "处理中…" : "移除并轮换密钥"}</button>
                {/if}
              {/if}
            </div>
            {#if pendingRemovalDeviceId === device.id}
              <div class="device-removal-confirmation" role="alert" aria-live="polite">
                <strong>确认移除“{device.name}”？</strong>
                <p>设备会立即断开并需要重新配对；空间密钥轮换时，本空间历史也会被清空。</p>
                <div>
                  <button
                    class="compact-danger-action"
                    type="button"
                    disabled={busyDeviceId === device.id}
                    on:click={() => removeDevice(device)}
                  >{busyDeviceId === device.id ? "正在移除…" : "确认移除"}</button>
                  <button
                    class="text-button"
                    type="button"
                    disabled={busyDeviceId === device.id}
                    on:click={() => (pendingRemovalDeviceId = "")}
                  >取消</button>
                </div>
              </div>
            {/if}
          {/if}
        </article>
      {/each}
    {/if}
  </div>
</section>
