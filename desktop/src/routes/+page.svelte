<script lang="ts">
  import ClipboardCard from "$lib/components/clipboard/ClipboardCard.svelte";
  import AboutPage from "$lib/components/about/AboutPage.svelte";
  import HistoryList from "$lib/components/clipboard/HistoryList.svelte";
  import HmacDiagnosticCard from "$lib/components/devices/HmacDiagnosticCard.svelte";
  import DeviceChips from "$lib/components/devices/DeviceChips.svelte";
  import NetworkDiagnosticsCard from "$lib/components/devices/NetworkDiagnosticsCard.svelte";
  import NetworkTroubleshootingCard from "$lib/components/devices/NetworkTroubleshootingCard.svelte";
  import PairingJoinDialog from "$lib/components/devices/PairingJoinDialog.svelte";
  import PocConnectCard from "$lib/components/devices/PocConnectCard.svelte";
  import StatusCard from "$lib/components/common/StatusCard.svelte";
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import { settingsSnapshot } from "$lib/stores/settings";
  import { autostartSnapshot } from "$lib/stores/autostart";
  import { shellSnapshot } from "$lib/stores/shell";
  import type { AppSettings, ThemeMode } from "$lib/types/settings";
  import type { SyncSpaceSummary } from "$lib/types/shell";
  import { listen } from "@tauri-apps/api/event";
  import { onMount } from "svelte";
  import packageMetadata from "../../package.json";

  let settingsVisible = false;
  let aboutVisible = false;
  let settingsSection: "general" | "devices" | "advanced" = "general";
  let pendingSpaceDeletionId = "";
  let expandedSpaceActionsId = "";
  let qrExpanded = false;
  let joinDialogVisible = false;

  $: if (qrExpanded && !$shellSnapshot.syncSpace.invitation) {
    qrExpanded = false;
  }

  async function removeSyncSpace(space: SyncSpaceSummary): Promise<void> {
    try {
      if (space.localRole === "member") {
        await shellSnapshot.leaveSyncSpace(space.id);
      } else {
        await shellSnapshot.deleteSyncSpace(space.id);
      }
      pendingSpaceDeletionId = "";
    } catch (_) {
      // The store exposes the actionable backend error inside the space panel.
    }
  }

  function invitationTargetSpace(): SyncSpaceSummary | null {
    const ownerSpaces = $shellSnapshot.syncSpace.spaces.filter((space) => space.localRole === "owner");
    return ownerSpaces.find((space) => space.id === $shellSnapshot.syncSpace.activeSpaceId) ?? ownerSpaces[0] ?? null;
  }

  async function createInvitationForCurrentOwner(): Promise<void> {
    const space = invitationTargetSpace();
    if (space) await shellSnapshot.createPairingInvitation(space.id);
  }

  async function refreshAfterDesktopJoin(): Promise<void> {
    await Promise.all([
      shellSnapshot.refreshSyncSpaces(),
      shellSnapshot.refreshTrustedDevices(),
      shellSnapshot.refreshHistorySummary(),
    ]);
  }

  onMount(() => {
    void shellSnapshot
      .startPocEventListeners()
      .then(() => shellSnapshot.startPocTransport())
      .then(() => shellSnapshot.refreshTrustedDevices());
    void shellSnapshot.startClipboardMonitor();
    void shellSnapshot.refreshHistorySummary();
    void shellSnapshot.loadRecentPocEndpoint();
    void shellSnapshot.ensureDefaultSyncSpace();
    void settingsSnapshot.load();
    void autostartSnapshot.load();
    const traySettingsListener = listen("settings://changed", () => settingsSnapshot.load());
    const trayDevicesListener = listen("tray://open-devices", () => {
      aboutVisible = false;
      settingsVisible = true;
      settingsSection = "devices";
      requestAnimationFrame(() => {
        document.getElementById("trusted-devices")?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    });
    const trayAboutListener = listen("tray://open-about", () => {
      settingsVisible = false;
      aboutVisible = true;
    });
    return () => {
      void traySettingsListener.then((unlisten) => unlisten());
      void trayDevicesListener.then((unlisten) => unlisten());
      void trayAboutListener.then((unlisten) => unlisten());
    };
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

<svelte:window
  on:keydown={(event) => {
    if (event.key === "Escape") {
      qrExpanded = false;
    }
  }}
/>

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
      </div>
      <p>局域网剪贴板同步</p>
    </div>
    <button
      class="icon-button"
      type="button"
      aria-label="打开设置"
      aria-expanded={settingsVisible}
      on:click={() => {
        aboutVisible = false;
        settingsVisible = !settingsVisible;
      }}>⚙</button
    >
  </header>

  {#if aboutVisible}
    <AboutPage version={packageMetadata.version} onBack={() => (aboutVisible = false)} />
  {:else}
    <div class="panel-main">
      <ClipboardCard
      current={$shellSnapshot.current}
      outbound={$shellSnapshot.outbound}
      onRead={() => shellSnapshot.readLocalClipboard()}
      onCopy={() => shellSnapshot.copyCurrentToClipboard()}
      onSend={() => shellSnapshot.sendCurrentToHarmony($settingsSnapshot.settings.syncEnabled)}
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
      onCopy={(itemId) => shellSnapshot.copyHistoryItem(itemId)}
      />
    </div>
  {/if}

  {#if settingsVisible}
    <section class="settings-popover" aria-label="设置">
      <div class="section-heading compact">
        <div>
          <h2>设置</h2>
          <p class="metadata">
            {$settingsSnapshot.state === "error"
              ? $settingsSnapshot.errorMessage
              : "更改后自动保存到本机"}
          </p>
        </div>
      </div>

      <nav class="settings-tabs" aria-label="设置分类">
        <button class:active={settingsSection === "general"} type="button" on:click={() => (settingsSection = "general")}>常规</button>
        <button class:active={settingsSection === "devices"} type="button" on:click={() => (settingsSection = "devices")}>设备</button>
        <button class:active={settingsSection === "advanced"} type="button" on:click={() => (settingsSection = "advanced")}>高级</button>
      </nav>

      {#if settingsSection === "general"}
        <div class="setting-grid">
        <label>
          <span class="setting-copy">
            <strong>开机自动启动</strong>
            <small>登录 Windows 后在托盘运行</small>
          </span>
          <input
            type="checkbox"
            aria-label="开机自动启动"
            checked={$autostartSnapshot.enabled}
            disabled={$autostartSnapshot.state === "loading" || $autostartSnapshot.state === "saving"}
            on:change={(event) =>
              autostartSnapshot.setEnabled(event.currentTarget.checked)}
          />
        </label>
        {#if $autostartSnapshot.errorMessage}
          <p class="setting-inline-error" role="status">{$autostartSnapshot.errorMessage}</p>
        {/if}
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
        <p class="settings-footnote">只在局域网同步纯文本；设置和历史保存在本机。</p>
      {:else if settingsSection === "devices"}

      <section class="device-entry-panel" aria-label="设备配对入口">
        <div>
          <strong>连接新设备</strong>
          <p>向手机、平板或电脑发出邀请，也可以加入另一台电脑。</p>
        </div>
        <div class="device-entry-actions">
          <button
            class="device-entry-button add-device-entry"
            type="button"
            disabled={!invitationTargetSpace() || $shellSnapshot.syncSpace.state === "inviting"}
            on:click={() => createInvitationForCurrentOwner()}
          >
            <span class="device-entry-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" role="img">
                <rect x="3.5" y="5" width="12" height="14" rx="3"></rect>
                <path d="M7.5 16h4"></path>
                <path d="M19 8v6M16 11h6"></path>
              </svg>
            </span>
            <span class="device-entry-copy">
              <strong>添加设备</strong>
              <small>生成配对邀请</small>
            </span>
            <span class="device-entry-chevron" aria-hidden="true">›</span>
          </button>
          <button
            class="device-entry-button join-device-entry"
            type="button"
            on:click={() => (joinDialogVisible = true)}
          >
            <span class="device-entry-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" role="img">
                <rect x="2.5" y="5" width="12" height="10" rx="2.5"></rect>
                <path d="M6 19h5M8.5 15v4"></path>
                <rect x="15.5" y="8" width="6" height="9" rx="1.8"></rect>
                <path d="M17.8 14.5h1.4"></path>
              </svg>
            </span>
            <span class="device-entry-copy">
              <strong>加入另一台电脑</strong>
              <small>粘贴邀请并连接</small>
            </span>
            <span class="device-entry-chevron" aria-hidden="true">›</span>
          </button>
        </div>
        {#if !invitationTargetSpace()}
          <p class="device-entry-hint">当前没有可发出邀请的协调端空间；仍可通过邀请加入另一台电脑。</p>
        {/if}
      </section>

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
            <p>添加设备前，请先创建一个同步空间。</p>
          </div>
        {:else}
          <div class="space-list">
            {#each $shellSnapshot.syncSpace.spaces as space (space.id)}
              <article class="space-card">
                <div>
                  <strong>{space.displayName}</strong>
                  <p>
                    #{space.shortId} ·
                    {space.localRole === "owner" ? "协调端" : "成员端"} ·
                    {$shellSnapshot.devices.filter((device) =>
                      device.trustKind === "trusted" && device.spaceId === space.id).length}
                    台可信设备
                  </p>
                </div>
                <div class="space-card-actions">
                  <span>
                    {$shellSnapshot.syncSpace.activeSpaceId === space.id
                      ? "当前"
                      : "可用"}
                  </span>
                  <div class="space-card-controls">
                    {#if space.localRole === "owner"}
                      <button
                        class="text-button"
                        type="button"
                        disabled={$shellSnapshot.syncSpace.state === "inviting"}
                        on:click={() => shellSnapshot.createPairingInvitation(space.id)}
                      >
                        添加设备
                      </button>
                    {/if}
                    <button
                      class="text-button"
                      type="button"
                      aria-expanded={expandedSpaceActionsId === space.id}
                      on:click={() => (expandedSpaceActionsId = expandedSpaceActionsId === space.id ? "" : space.id)}
                    >更多</button>
                  </div>
                </div>
                {#if expandedSpaceActionsId === space.id}
                  <div class="space-card-more">
                    <button
                      class="text-button"
                      type="button"
                      disabled={$shellSnapshot.syncSpace.state === "loading" ||
                        $shellSnapshot.syncSpace.activeSpaceId === space.id}
                      on:click={() => shellSnapshot.selectActiveSyncSpace(space.id)}
                    >{$shellSnapshot.syncSpace.activeSpaceId === space.id ? "当前空间" : "设为当前"}</button>
                    <button
                      class="text-button danger-action"
                      type="button"
                      disabled={$shellSnapshot.syncSpace.state === "loading" ||
                        (space.localRole === "owner" && $shellSnapshot.syncSpace.spaces.length <= 1)}
                      on:click={() => (pendingSpaceDeletionId = space.id)}
                    >{space.localRole === "member" ? "离开空间" : "删除空间"}</button>
                  </div>
                {/if}
                {#if pendingSpaceDeletionId === space.id}
                  <div class="device-removal-confirmation space-deletion-confirmation" role="alert">
                    <strong>{space.localRole === "member" ? "确认离开" : "确认删除"}“{space.displayName}”？</strong>
                    <p>{space.localRole === "member"
                      ? "与协调端的可信连接、该空间的本地记录和密钥将被移除；再次加入需要新的邀请。"
                      : "该空间、本地同步记录和旧密钥引用将被删除，操作无法撤销。有可信设备在线或尚未移除时会拒绝删除。"}</p>
                    <div>
                      <button
                        class="compact-danger-action"
                        type="button"
                        disabled={$shellSnapshot.syncSpace.state === "loading"}
                        on:click={() => removeSyncSpace(space)}
                      >{space.localRole === "member" ? "确认离开" : "确认删除"}</button>
                      <button
                        class="text-button"
                        type="button"
                        disabled={$shellSnapshot.syncSpace.state === "loading"}
                        on:click={() => (pendingSpaceDeletionId = "")}
                      >取消</button>
                    </div>
                  </div>
                {/if}
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
                <span>配对确认码</span>
                <strong>{$shellSnapshot.syncSpace.invitation.confirmationCode}</strong>
              </div>
              <div class="invitation-qr" aria-label="配对二维码">
                {@html $shellSnapshot.syncSpace.invitation.qrSvg}
                <span>用鸿蒙端扫码导入，或复制邀请字符串手动导入。</span>
                <button
                  class="invitation-qr-expand"
                  type="button"
                  on:click={() => (qrExpanded = true)}
                >放大扫码</button>
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

      <div id="trusted-devices" class="settings-anchor">
        <DeviceChips
          devices={$shellSnapshot.devices.filter((device) => device.trustKind !== "poc")}
          onRename={(deviceId, name) => shellSnapshot.renameTrustedDevice(deviceId, name)}
          onRemove={(deviceId) => shellSnapshot.removeTrustedDevice(deviceId)}
          canRemove={(device) =>
            $shellSnapshot.syncSpace.spaces.some((space) =>
              space.id === device.spaceId && space.localRole === "owner")}
        />
      </div>
      {:else}
        <p class="advanced-intro">仅在连接或密钥异常时使用。诊断信息不包含剪贴板正文或密钥。</p>

        <HmacDiagnosticCard
          state={$shellSnapshot.syncSpace.state}
          diagnostic={$shellSnapshot.syncSpace.hmacDiagnostic}
          onRun={() => shellSnapshot.runSpaceHmacDiagnostic()}
        />

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
      {/if}
    </section>
  {/if}

  {#if qrExpanded && $shellSnapshot.syncSpace.invitation}
    <div class="qr-dialog-layer">
      <button
        class="qr-dialog-backdrop"
        type="button"
        aria-label="关闭放大二维码"
        on:click={() => (qrExpanded = false)}
      ></button>
      <dialog
        open
        class="qr-dialog-card"
        aria-modal="true"
        aria-labelledby="qr-dialog-title"
        aria-describedby="qr-dialog-description"
      >
        <header class="qr-dialog-header">
          <div>
            <h2 id="qr-dialog-title">扫描配对二维码</h2>
            <p id="qr-dialog-description">请用鸿蒙端保持镜头稳定并完整框住二维码。</p>
          </div>
          <button
            class="qr-dialog-close"
            type="button"
            aria-label="关闭放大二维码"
            on:click={() => (qrExpanded = false)}
          >×</button>
        </header>
        <div class="expanded-invitation-qr" aria-label="放大的配对二维码">
          {@html $shellSnapshot.syncSpace.invitation.qrSvg}
        </div>
        <div class="qr-dialog-confirmation">
          <span>配对确认码</span>
          <strong>{$shellSnapshot.syncSpace.invitation.confirmationCode}</strong>
        </div>
        <p class="qr-dialog-expiry">
          邀请将在 {$shellSnapshot.syncSpace.invitation.expiresAt} 到期；关闭后仍可复制邀请字符串。
        </p>
      </dialog>
    </div>
  {/if}

  {#if joinDialogVisible}
    <PairingJoinDialog
      onClose={() => (joinDialogVisible = false)}
      onConnected={() => refreshAfterDesktopJoin()}
    />
  {/if}

  {#if !aboutVisible}
    <footer>
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
  {/if}
</main>
