<script lang="ts">
  import ClipboardCard from "$lib/components/clipboard/ClipboardCard.svelte";
  import HistoryList from "$lib/components/clipboard/HistoryList.svelte";
  import DeviceChips from "$lib/components/devices/DeviceChips.svelte";
  import StatusCard from "$lib/components/common/StatusCard.svelte";
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import { shellSnapshot } from "$lib/stores/shell";
  import { onMount } from "svelte";

  onMount(() => {
    void shellSnapshot.startPocTransport();
    void shellSnapshot.startPocEventListeners();
    void shellSnapshot.startClipboardMonitor();
  });
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
      <h1>蛋定 Clip</h1>
      <p>局域网剪贴板同步</p>
    </div>
    <button class="icon-button" type="button" aria-label="打开设置">⚙</button>
  </header>

  <StatusCard
    state={$shellSnapshot.connection.state}
    title={$shellSnapshot.connection.title}
    description={$shellSnapshot.connection.description}
  />

  <ClipboardCard
    current={$shellSnapshot.current}
    onRead={() => shellSnapshot.readLocalClipboard()}
    onCopy={() => shellSnapshot.copyCurrentToClipboard()}
  />

  <DeviceChips devices={$shellSnapshot.devices} />

  <HistoryList history={$shellSnapshot.history} />

  <footer>
    <span>一步一点，不着急</span>
    <button class="sync-toggle" type="button">
      <StatusDot state={$shellSnapshot.syncEnabled ? "online" : "paused"} />
      同步已开启
    </button>
  </footer>
</main>
