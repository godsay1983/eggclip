<script lang="ts">
  import ClipboardCard from "$lib/components/clipboard/ClipboardCard.svelte";
  import HistoryList from "$lib/components/clipboard/HistoryList.svelte";
  import DeviceChips from "$lib/components/devices/DeviceChips.svelte";
  import PocConnectCard from "$lib/components/devices/PocConnectCard.svelte";
  import StatusCard from "$lib/components/common/StatusCard.svelte";
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import { settingsSnapshot } from "$lib/stores/settings";
  import { shellSnapshot } from "$lib/stores/shell";
  import type { AppSettings } from "$lib/types/settings";
  import { onMount } from "svelte";

  let settingsVisible = false;

  onMount(() => {
    void shellSnapshot
      .startPocEventListeners()
      .then(() => shellSnapshot.startPocTransport());
    void shellSnapshot.startClipboardMonitor();
    void settingsSnapshot.load();
  });

  async function saveSetting<K extends keyof AppSettings>(
    key: K,
    value: AppSettings[K],
  ) {
    await settingsSnapshot.save({
      ...$settingsSnapshot.settings,
      [key]: value,
    });
  }

  function historyLimitFromValue(value: string): AppSettings["historyLimit"] {
    const parsed = Number(value);
    return [0, 20, 50, 100].includes(parsed)
      ? (parsed as AppSettings["historyLimit"])
      : 50;
  }
</script>

<svelte:head>
  <meta
    name="description"
    content="EggClip 蛋定 Clip 局域网剪贴板同步"
  />
</svelte:head>

<main class="panel-shell">
  <header class="brand-row">
    <div class="brand-mark" aria-hidden="true">🥚</div>
    <div class="brand-copy">
      <div class="title-line">
        <h1>蛋定 Clip</h1>
        <span class="beta-badge">Beta</span>
      </div>
      <p>只在局域网内同步纯文本剪贴板</p>
      <div class="brand-pills" aria-label="产品边界">
        <span>局域网</span>
        <span>无账号</span>
        <span>最近 50 条</span>
      </div>
    </div>
    <button
      class="icon-button"
      type="button"
      aria-label="打开设置"
      aria-expanded={settingsVisible}
      on:click={() => {
        settingsVisible = !settingsVisible;
      }}>⚙</button
    >
  </header>

  <StatusCard
    state={$shellSnapshot.connection.state}
    title={$shellSnapshot.connection.title}
    description={$shellSnapshot.connection.description}
  />

  <PocConnectCard />

  <ClipboardCard
    current={$shellSnapshot.current}
    onRead={() => shellSnapshot.readLocalClipboard()}
    onCopy={() => shellSnapshot.copyCurrentToClipboard()}
    onSendPoc={() => shellSnapshot.sendCurrentToPocPeer()}
  />

  <DeviceChips devices={$shellSnapshot.devices} />

  <HistoryList history={$shellSnapshot.history} />

  {#if settingsVisible}
    <section class="settings-popover" aria-label="设置">
      <div class="section-heading compact">
        <div>
          <h2>设置</h2>
          <p class="metadata">
            {$settingsSnapshot.state === "error"
              ? $settingsSnapshot.errorMessage
              : "保存到本机数据库，不上传云端"}
          </p>
        </div>
        <button
          class="text-button"
          type="button"
          on:click={() => settingsSnapshot.load()}>重新读取</button
        >
      </div>

      <p class="settings-note">
        设置只保存在本机；HarmonyOS 读取剪贴板仍必须由系统 PasteButton 触发。
      </p>

      <div class="setting-grid">
        <label>
          <span>自动同步</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.syncEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("syncEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>自动接收</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.autoReceiveEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("autoReceiveEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>桌面自动写入剪贴板</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.autoWriteEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("autoWriteEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>保存历史</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.historyEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("historyEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>历史数量</span>
          <select
            value={$settingsSnapshot.settings.historyLimit}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("historyLimit", historyLimitFromValue(event.currentTarget.value))}
          >
            <option value="0">不保存</option>
            <option value="20">20 条</option>
            <option value="50">50 条</option>
            <option value="100">100 条</option>
          </select>
        </label>
        <label>
          <span>最长保留天数</span>
          <input
            type="number"
            min="0"
            step="1"
            value={$settingsSnapshot.settings.retentionDays}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("retentionDays", Number(event.currentTarget.value))}
          />
        </label>
      </div>
    </section>
  {/if}

  <footer>
    <span>本机常驻 · 局域网同步</span>
    <button
      class="sync-toggle"
      type="button"
      on:click={() =>
        settingsSnapshot.setSyncEnabled(!$settingsSnapshot.settings.syncEnabled)}
    >
      <StatusDot state={$settingsSnapshot.settings.syncEnabled ? "online" : "paused"} />
      {$settingsSnapshot.settings.syncEnabled ? "同步已开启" : "同步已暂停"}
    </button>
  </footer>
</main>
