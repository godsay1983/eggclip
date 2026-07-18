<script lang="ts">
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import { effectiveLocale, formatDateTime, text } from "$lib/i18n";
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
      return text($effectiveLocale, "status.online");
    }
    if (state === "connecting") {
      return text($effectiveLocale, "status.connecting");
    }
    if (state === "authFailed") {
      return text($effectiveLocale, "status.authFailed");
    }
    if (state === "paused") {
      return text($effectiveLocale, "status.paused");
    }
    return text($effectiveLocale, "status.offline");
  }

  function trustLabel(kind: DeviceSummary["trustKind"]) {
    if (kind === "trusted") {
      return text($effectiveLocale, "device.trusted");
    }
    if (kind === "poc") {
      return text($effectiveLocale, "device.experimental");
    }
    return text($effectiveLocale, "device.pending");
  }

  function deviceName(device: DeviceSummary): string {
    if (device.trustKind === "poc") return text($effectiveLocale, "device.pocName");
    if (device.trustKind === "placeholder") return text($effectiveLocale, "device.placeholderName");
    return device.name;
  }

  function fingerprint(device: DeviceSummary): string {
    if (device.trustKind === "poc") return text($effectiveLocale, "device.notPaired");
    if (device.trustKind === "placeholder") return text($effectiveLocale, "device.waitingPairing");
    return device.shortFingerprint || text($effectiveLocale, "common.notRecorded");
  }

  function lastSeen(device: DeviceSummary): string {
    if (device.state === "online") return text($effectiveLocale, "device.sessionOnline");
    if (device.lastSeenAtMs) return formatDateTime(device.lastSeenAtMs, $effectiveLocale);
    return text($effectiveLocale, "common.notRecorded");
  }

  function deviceNote(device: DeviceSummary): string {
    if (device.trustKind === "poc") return text($effectiveLocale, "device.pocHint");
    if (device.trustKind === "placeholder") return text($effectiveLocale, "device.emptyHint");
    return text($effectiveLocale, device.state === "online" ? "device.authenticatedOnline" : "device.waitingReconnect");
  }
</script>

<section class="device-section">
  <div class="section-heading compact">
    <div>
      <h2>{text($effectiveLocale, "device.title")}</h2>
      <span class="metadata">{text($effectiveLocale, "device.subtitle")}</span>
    </div>
  </div>
  <div class="device-list">
    {#if devices.length === 0}
      <div class="device-empty">
        <span aria-hidden="true">◇</span>
        <div>
          <strong>{text($effectiveLocale, "device.empty")}</strong>
          <p>{text($effectiveLocale, "device.emptyHint")}</p>
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
          title={`${deviceName(device)}: ${statusLabel(device.state)}`}
        >
          <div class="device-card-header">
            <StatusDot state={device.state} />
            <div>
              <strong>{deviceName(device)}</strong>
              <p>{trustLabel(device.trustKind)} · {statusLabel(device.state)}</p>
            </div>
          </div>
          <dl class="device-meta-grid">
            <div>
              <dt>{text($effectiveLocale, "device.fingerprint")}</dt>
              <dd>{fingerprint(device)}</dd>
            </div>
            <div>
              <dt>{text($effectiveLocale, "device.lastOnline")}</dt>
              <dd>{lastSeen(device)}</dd>
            </div>
            {#if device.endpoint}
              <div>
                <dt>{text($effectiveLocale, "device.endpoint")}</dt>
                <dd>{device.endpoint}</dd>
              </div>
            {/if}
          </dl>
          <p class="device-note">{deviceNote(device)}</p>
          {#if device.trustKind === "trusted"}
            <div class="device-management-actions">
              {#if editingDeviceId === device.id}
                <input
                  aria-label={text($effectiveLocale, "device.nameLabel")}
                  maxlength="32"
                  bind:value={editingName}
                  disabled={busyDeviceId === device.id}
                />
                <button
                  class="text-button"
                  type="button"
                  disabled={busyDeviceId === device.id || editingName.trim().length === 0}
                  on:click={() => saveName(device)}
                >{text($effectiveLocale, "common.save")}</button>
                <button class="text-button" type="button" on:click={() => (editingDeviceId = "")}>{text($effectiveLocale, "common.cancel")}</button>
              {:else}
                <button
                  class="text-button"
                  type="button"
                  disabled={busyDeviceId === device.id}
                  on:click={() => {
                    editingDeviceId = device.id;
                    editingName = device.name;
                  }}
                >{text($effectiveLocale, "device.rename")}</button>
                {#if canRemove(device)}
                  <button
                    class="text-button danger-action"
                    type="button"
                    disabled={busyDeviceId === device.id}
                    on:click={() => (pendingRemovalDeviceId = device.id)}
                  >{text($effectiveLocale, busyDeviceId === device.id ? "common.loading" : "device.remove")}</button>
                {/if}
              {/if}
            </div>
            {#if pendingRemovalDeviceId === device.id}
              <div class="device-removal-confirmation" role="alert" aria-live="polite">
                <strong>{text($effectiveLocale, "device.removeQuestion", { name: device.name })}</strong>
                <p>{text($effectiveLocale, "device.removeHint")}</p>
                <div>
                  <button
                    class="compact-danger-action"
                    type="button"
                    disabled={busyDeviceId === device.id}
                    on:click={() => removeDevice(device)}
                  >{text($effectiveLocale, busyDeviceId === device.id ? "device.removing" : "device.confirmRemove")}</button>
                  <button
                    class="text-button"
                    type="button"
                    disabled={busyDeviceId === device.id}
                    on:click={() => (pendingRemovalDeviceId = "")}
                  >{text($effectiveLocale, "common.cancel")}</button>
                </div>
              </div>
            {/if}
          {/if}
        </article>
      {/each}
    {/if}
  </div>
</section>
