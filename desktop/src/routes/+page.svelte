<script lang="ts">
  import ClipboardCard from "$lib/components/clipboard/ClipboardCard.svelte";
  import HistoryList from "$lib/components/clipboard/HistoryList.svelte";
  import DeviceChips from "$lib/components/devices/DeviceChips.svelte";
  import NetworkDiagnosticsCard from "$lib/components/devices/NetworkDiagnosticsCard.svelte";
  import NetworkTroubleshootingCard from "$lib/components/devices/NetworkTroubleshootingCard.svelte";
  import PocConnectCard from "$lib/components/devices/PocConnectCard.svelte";
  import StatusCard from "$lib/components/common/StatusCard.svelte";
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import { settingsSnapshot } from "$lib/stores/settings";
  import { shellSnapshot } from "$lib/stores/shell";
  import type { AppSettings, ThemeMode } from "$lib/types/settings";
  import { onMount } from "svelte";

  let settingsVisible = false;

  onMount(() => {
    void shellSnapshot
      .startPocEventListeners()
      .then(() => shellSnapshot.startPocTransport());
    void shellSnapshot.startClipboardMonitor();
    void shellSnapshot.refreshHistorySummary();
    void shellSnapshot.loadRecentPocEndpoint();
    void shellSnapshot.ensureDefaultSyncSpace();
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
    if (key === "historyEnabled" || key === "historyLimit" || key === "retentionDays") {
      await shellSnapshot.refreshHistorySummary();
    }
  }

  function historyLimitFromValue(value: string): AppSettings["historyLimit"] {
    const parsed = Number(value);
    return [0, 20, 50, 100].includes(parsed)
      ? (parsed as AppSettings["historyLimit"])
      : 50;
  }

  function themeModeFromValue(value: string): ThemeMode {
    return value === "light" || value === "dark" ? value : "system";
  }

  function applyTheme(themeMode: ThemeMode) {
    if (typeof document === "undefined") {
      return;
    }
    document.documentElement.dataset.theme = themeMode;
  }

  $: applyTheme($settingsSnapshot.settings.themeMode);
  $: shellSnapshot.setPocReceivePolicy(
    $settingsSnapshot.settings.syncEnabled,
    $settingsSnapshot.settings.autoReceiveEnabled,
  );
</script>

<svelte:head>
  <meta
    name="description"
    content="EggClip 蛋定 Clip 局域网剪贴板同步"
  />
</svelte:head>

<main class="panel-shell">
  <header class="brand-row">
    <img class="brand-mark" src="/app-icon.png" alt="" aria-hidden="true" />
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

  <div class="panel-main">
    <ClipboardCard
      current={$shellSnapshot.current}
      outbound={$shellSnapshot.outbound}
      onRead={() => shellSnapshot.readLocalClipboard()}
      onCopy={() => shellSnapshot.copyCurrentToClipboard()}
      onSendPoc={() => shellSnapshot.sendCurrentToPocPeer($settingsSnapshot.settings.syncEnabled)}
      sendDisabled={!$settingsSnapshot.settings.syncEnabled}
      sendLabel={$settingsSnapshot.settings.syncEnabled ? "发送到 Harmony" : "同步已暂停"}
    />

    <HistoryList
      history={{
        ...$shellSnapshot.history,
        limit: $settingsSnapshot.settings.historyLimit,
      }}
      historyEnabled={$settingsSnapshot.settings.historyEnabled && $settingsSnapshot.settings.historyLimit > 0}
      onClear={() => shellSnapshot.clearHistory()}
      onDelete={(itemId) => shellSnapshot.deleteHistoryItem(itemId)}
    />
  </div>

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

      <section class="privacy-summary" aria-label="隐私说明">
        <div>
          <h3>隐私边界</h3>
          <p>EggClip v1 只在局域网内传输纯文本，不使用账号、云同步或公网中继。</p>
        </div>
        <ul>
          <li>历史默认保存在本机数据库，可关闭或清空。</li>
          <li>桌面端可自动写入已认证实时文本；POC 连接仍只用于开发验证。</li>
          <li>诊断只显示连接状态，不显示正文、摘要、邀请或密钥。</li>
        </ul>
      </section>

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
            value={String($settingsSnapshot.settings.historyLimit)}
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
        <label>
          <span>主题</span>
          <select
            value={$settingsSnapshot.settings.themeMode}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("themeMode", themeModeFromValue(event.currentTarget.value))}
          >
            <option value="system">跟随系统</option>
            <option value="light">浅色</option>
            <option value="dark">深色</option>
          </select>
        </label>
      </div>

      <div class="settings-divider"></div>

      <section class="space-summary" aria-label="同步空间">
        <div class="section-heading compact">
          <div>
            <h2>同步空间</h2>
            <p class="metadata">
              {$shellSnapshot.syncSpace.errorMessage ??
                "空间密钥保存到系统凭据库，界面不显示密钥"}
            </p>
          </div>
          <button
            class="text-button"
            type="button"
            disabled={$shellSnapshot.syncSpace.state === "creating"}
            on:click={() => shellSnapshot.createDefaultSyncSpace()}
          >
            {$shellSnapshot.syncSpace.spaces.length > 0 ? "新增空间" : "创建默认空间"}
          </button>
        </div>

        {#if $shellSnapshot.syncSpace.spaces.length === 0}
          <div class="space-empty">
            <strong>尚未创建正式同步空间</strong>
            <p>当前 POC 连接仍可手动验证收发；正式配对前需要先创建本地空间和 256-bit spaceKey。</p>
          </div>
        {:else}
          <div class="space-list">
            {#each $shellSnapshot.syncSpace.spaces as space (space.id)}
              <article class="space-card">
                <div>
                  <strong>{space.displayName}</strong>
                  <p>空间 #{space.shortId} · key v{space.keyVersion} · {space.createdAt}</p>
                </div>
                <div class="space-card-actions">
                  <span>{space.keyRefKind === "credential" ? "凭据库" : "待检查"}</span>
                  <button
                    class="text-button"
                    type="button"
                    disabled={$shellSnapshot.syncSpace.state === "inviting"}
                    on:click={() => shellSnapshot.createPairingInvitation(space.id)}
                  >
                    生成邀请
                  </button>
                </div>
              </article>
            {/each}
          </div>
          {#if $shellSnapshot.syncSpace.invitation}
            <div class="invitation-card">
              <strong>配对邀请已生成</strong>
              <p>
                {$shellSnapshot.syncSpace.invitation.spaceDisplayName} ·
                {$shellSnapshot.syncSpace.invitation.expiresInSeconds / 60} 分钟内有效 ·
                到期 {$shellSnapshot.syncSpace.invitation.expiresAt}
              </p>
              <div class="confirmation-code">
                <span>人工确认码</span>
                <strong>{$shellSnapshot.syncSpace.invitation.confirmationCode}</strong>
              </div>
              <button
                class="secondary-action invitation-copy"
                type="button"
                disabled={$shellSnapshot.syncSpace.state === "copyingInvitation"}
                on:click={() =>
                  shellSnapshot.copyPairingInvitation(
                    $shellSnapshot.syncSpace.invitation?.invitationString ?? "",
                  )}
              >
                <span aria-hidden="true">⧉</span>
                <strong>
                  {$shellSnapshot.syncSpace.state === "copyingInvitation"
                    ? "正在复制邀请"
                    : "复制邀请"}
                </strong>
                <em>安全</em>
              </button>
              {#if $shellSnapshot.syncSpace.invitationCopiedAt}
                <p class="copy-hint">
                  已在 {$shellSnapshot.syncSpace.invitationCopiedAt} 复制；本机历史会忽略这次写入。
                </p>
              {/if}
              <p>
                发行设备 {$shellSnapshot.syncSpace.invitation.issuerDeviceName} ·
                #{$shellSnapshot.syncSpace.invitation.issuerShortFingerprint}。邀请字符串包含一次性秘密，不在界面展开明文；请只发给要配对的设备。
              </p>
            </div>
          {/if}
        {/if}
      </section>

      <div class="settings-divider"></div>

      <StatusCard
        state={$shellSnapshot.connection.state}
        title={$shellSnapshot.connection.title}
        description={$shellSnapshot.connection.description}
      />

      <PocConnectCard />

      <NetworkDiagnosticsCard
        transport={$shellSnapshot.pocTransport}
        onRefresh={() => shellSnapshot.refreshPocTransportStatus()}
      />

      <NetworkTroubleshootingCard transport={$shellSnapshot.pocTransport} />

      <DeviceChips devices={$shellSnapshot.devices} />
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
