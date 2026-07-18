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
  import { canManageSyncSpace } from "$lib/pairing-join";
  import type { AppSettings, LanguageMode, ThemeMode } from "$lib/types/settings";
  import type { SyncSpaceSummary } from "$lib/types/shell";
  import { listen } from "@tauri-apps/api/event";
  import { onMount } from "svelte";
  import packageMetadata from "../../package.json";
  import { effectiveLocale, formatTime, formatUiMessage, pluralText, text } from "$lib/i18n";

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
    const ownerSpaces = $shellSnapshot.syncSpace.spaces.filter((space) =>
      canManageSyncSpace(space.localRole, "invite"));
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

  function languageModeFromValue(value: string): LanguageMode {
    return value === "zh-CN" || value === "en-US" ? value : "system";
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
    content={text($effectiveLocale, "app.description")}
  />
</svelte:head>

<main class="panel-shell">
  <header class="brand-row">
    <img class="brand-mark" src="/app-icon.png" alt="" aria-hidden="true" />
    <div class="brand-copy">
      <div class="title-line">
        <h1>{text($effectiveLocale, "app.title")}</h1>
      </div>
      <p>{text($effectiveLocale, "app.tagline")}</p>
    </div>
    <button
      class="icon-button"
      type="button"
      aria-label={text($effectiveLocale, "settings.open")}
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
      sendLabel={text($effectiveLocale, $settingsSnapshot.settings.syncEnabled ? "clipboard.sendHarmony" : "settings.syncPaused")}
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
    <section class="settings-popover" aria-label={text($effectiveLocale, "settings.title")}>
      <div class="section-heading compact">
        <div>
          <h2>{text($effectiveLocale, "settings.title")}</h2>
          <p class="metadata">
            {$settingsSnapshot.state === "error"
              ? $settingsSnapshot.errorMessage
                ? formatUiMessage($effectiveLocale, $settingsSnapshot.errorMessage)
                : ""
              : text($effectiveLocale, "settings.autoSave")}
          </p>
        </div>
      </div>

      <nav class="settings-tabs" aria-label={text($effectiveLocale, "settings.categories")}>
        <button class:active={settingsSection === "general"} type="button" on:click={() => (settingsSection = "general")}>{text($effectiveLocale, "settings.general")}</button>
        <button class:active={settingsSection === "devices"} type="button" on:click={() => (settingsSection = "devices")}>{text($effectiveLocale, "settings.devices")}</button>
        <button class:active={settingsSection === "advanced"} type="button" on:click={() => (settingsSection = "advanced")}>{text($effectiveLocale, "settings.advanced")}</button>
      </nav>

      {#if settingsSection === "general"}
        <div class="setting-grid">
        <label>
          <span class="setting-copy">
            <strong>{text($effectiveLocale, "settings.autostart")}</strong>
            <small>{text($effectiveLocale, "settings.autostartHint")}</small>
          </span>
          <input
            type="checkbox"
            aria-label={text($effectiveLocale, "settings.autostart")}
            checked={$autostartSnapshot.enabled}
            disabled={$autostartSnapshot.state === "loading" || $autostartSnapshot.state === "saving"}
            on:change={(event) =>
              autostartSnapshot.setEnabled(event.currentTarget.checked)}
          />
        </label>
        {#if $autostartSnapshot.errorMessage}
          <p class="setting-inline-error" role="status">{formatUiMessage($effectiveLocale, $autostartSnapshot.errorMessage)}</p>
        {/if}
        <label>
          <span>{text($effectiveLocale, "settings.sync")}</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.syncEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("syncEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>{text($effectiveLocale, "settings.receive")}</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.autoReceiveEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("autoReceiveEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>{text($effectiveLocale, "settings.autoWrite")}</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.autoWriteEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("autoWriteEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>{text($effectiveLocale, "settings.history")}</span>
          <input
            type="checkbox"
            checked={$settingsSnapshot.settings.historyEnabled}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("historyEnabled", event.currentTarget.checked)}
          />
        </label>
        <label>
          <span>{text($effectiveLocale, "settings.historyLimit")}</span>
          <select
            value={String($settingsSnapshot.settings.historyLimit)}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("historyLimit", historyLimitFromValue(event.currentTarget.value))}
          >
            <option value="0">{text($effectiveLocale, "settings.historyNone")}</option>
            <option value="20">{pluralText($effectiveLocale, 20, "settings.historyCountOne", "settings.historyCountOther")}</option>
            <option value="50">{pluralText($effectiveLocale, 50, "settings.historyCountOne", "settings.historyCountOther")}</option>
            <option value="100">{pluralText($effectiveLocale, 100, "settings.historyCountOne", "settings.historyCountOther")}</option>
          </select>
        </label>
        <label>
          <span>{text($effectiveLocale, "settings.retention")}</span>
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
          <span>{text($effectiveLocale, "settings.theme")}</span>
          <select
            value={$settingsSnapshot.settings.themeMode}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("themeMode", themeModeFromValue(event.currentTarget.value))}
          >
            <option value="system">{text($effectiveLocale, "settings.themeSystem")}</option>
            <option value="light">{text($effectiveLocale, "settings.themeLight")}</option>
            <option value="dark">{text($effectiveLocale, "settings.themeDark")}</option>
          </select>
        </label>
        <label>
          <span class="setting-copy">
            <strong>{text($effectiveLocale, "settings.language")}</strong>
            <small>{text($effectiveLocale, "settings.languageHint")}</small>
          </span>
          <select
            value={$settingsSnapshot.settings.languageMode}
            disabled={$settingsSnapshot.state === "saving"}
            on:change={(event) =>
              saveSetting("languageMode", languageModeFromValue(event.currentTarget.value))}
          >
            <option value="system">{text($effectiveLocale, "language.system")}</option>
            <option value="zh-CN">{text($effectiveLocale, "language.zhCN")}</option>
            <option value="en-US">{text($effectiveLocale, "language.enUS")}</option>
          </select>
        </label>
        </div>
        <p class="settings-footnote">{text($effectiveLocale, "settings.footnote")}</p>
      {:else if settingsSection === "devices"}

      <section class="device-entry-panel" aria-label={text($effectiveLocale, "device.entryLabel")}>
        <div>
          <strong>{text($effectiveLocale, "device.connectNew")}</strong>
          <p>{text($effectiveLocale, "device.connectNewHint")}</p>
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
              <strong>{text($effectiveLocale, "device.add")}</strong>
              <small>{text($effectiveLocale, "device.addHint")}</small>
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
              <strong>{text($effectiveLocale, "device.joinComputer")}</strong>
              <small>{text($effectiveLocale, "device.joinHint")}</small>
            </span>
            <span class="device-entry-chevron" aria-hidden="true">›</span>
          </button>
        </div>
        {#if !invitationTargetSpace()}
          <p class="device-entry-hint">{text($effectiveLocale, "device.noOwnerSpace")}</p>
        {/if}
      </section>

      <section class="space-summary" aria-label={text($effectiveLocale, "space.label")}>
        <div class="section-heading compact">
          <div>
            <h2>{text($effectiveLocale, "space.label")}</h2>
            <p class="metadata">
              {$shellSnapshot.syncSpace.errorMessage
                ? formatUiMessage($effectiveLocale, $shellSnapshot.syncSpace.errorMessage)
                : text($effectiveLocale, "space.keySafe")}
            </p>
          </div>
          <button
            class="text-button"
            type="button"
            disabled={$shellSnapshot.syncSpace.state === "creating"}
            on:click={() => shellSnapshot.createDefaultSyncSpace()}
          >
            {text($effectiveLocale, $shellSnapshot.syncSpace.spaces.length > 0 ? "space.add" : "space.createDefault")}
          </button>
        </div>

        {#if $shellSnapshot.syncSpace.spaces.length === 0}
          <div class="space-empty">
            <strong>{text($effectiveLocale, "space.empty")}</strong>
            <p>{text($effectiveLocale, "space.emptyHint")}</p>
          </div>
        {:else}
          <div class="space-list">
            {#each $shellSnapshot.syncSpace.spaces as space (space.id)}
              <article class="space-card">
                <div>
                  <strong>{space.displayName}</strong>
                  <p>
                    #{space.shortId} ·
                    {text($effectiveLocale, space.localRole === "owner" ? "space.owner" : "space.member")} ·
                    {pluralText(
                      $effectiveLocale,
                      $shellSnapshot.devices.filter((device) => device.trustKind === "trusted" && device.spaceId === space.id).length,
                      "space.deviceCountOne",
                      "space.deviceCountOther",
                    )}
                  </p>
                </div>
                <div class="space-card-actions">
                  <span>
                    {$shellSnapshot.syncSpace.activeSpaceId === space.id
                      ? text($effectiveLocale, "space.current")
                      : text($effectiveLocale, "space.available")}
                  </span>
                  <div class="space-card-controls">
                    {#if space.localRole === "owner"}
                      <button
                        class="text-button"
                        type="button"
                        disabled={$shellSnapshot.syncSpace.state === "inviting"}
                        on:click={() => shellSnapshot.createPairingInvitation(space.id)}
                      >
                        {text($effectiveLocale, "device.add")}
                      </button>
                    {/if}
                    <button
                      class="text-button"
                      type="button"
                      aria-expanded={expandedSpaceActionsId === space.id}
                      on:click={() => (expandedSpaceActionsId = expandedSpaceActionsId === space.id ? "" : space.id)}
                    >{text($effectiveLocale, "common.more")}</button>
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
                    >{text($effectiveLocale, $shellSnapshot.syncSpace.activeSpaceId === space.id ? "space.currentSpace" : "space.makeCurrent")}</button>
                    <button
                      class="text-button danger-action"
                      type="button"
                      disabled={$shellSnapshot.syncSpace.state === "loading" ||
                        (space.localRole === "owner" && $shellSnapshot.syncSpace.spaces.length <= 1)}
                      on:click={() => (pendingSpaceDeletionId = space.id)}
                    >{text($effectiveLocale, space.localRole === "member" ? "space.leave" : "space.delete")}</button>
                  </div>
                {/if}
                {#if pendingSpaceDeletionId === space.id}
                  <div class="device-removal-confirmation space-deletion-confirmation" role="alert">
                    <strong>{text($effectiveLocale, "space.confirmQuestion", {
                      action: text($effectiveLocale, space.localRole === "member" ? "space.confirmLeave" : "space.confirmDelete"),
                      name: space.displayName
                    })}</strong>
                    <p>{text($effectiveLocale, space.localRole === "member" ? "space.leaveHint" : "space.deleteHint")}</p>
                    <div>
                      <button
                        class="compact-danger-action"
                        type="button"
                        disabled={$shellSnapshot.syncSpace.state === "loading"}
                        on:click={() => removeSyncSpace(space)}
                      >{text($effectiveLocale, space.localRole === "member" ? "space.confirmLeave" : "space.confirmDelete")}</button>
                      <button
                        class="text-button"
                        type="button"
                        disabled={$shellSnapshot.syncSpace.state === "loading"}
                        on:click={() => (pendingSpaceDeletionId = "")}
                      >{text($effectiveLocale, "common.cancel")}</button>
                    </div>
                  </div>
                {/if}
              </article>
            {/each}
          </div>
          {#if $shellSnapshot.syncSpace.invitation}
            <div class="invitation-card">
              <strong>{text($effectiveLocale, "pairing.generated")}</strong>
              <p>
                {$shellSnapshot.syncSpace.invitation.spaceDisplayName} ·
                {pluralText(
                  $effectiveLocale,
                  Math.max(1, Math.ceil($shellSnapshot.syncSpace.invitation.expiresInSeconds / 60)),
                  "pairing.validForOne",
                  "pairing.validForOther",
                  {
                    minutes: Math.max(1, Math.ceil($shellSnapshot.syncSpace.invitation.expiresInSeconds / 60)),
                    time: formatTime($shellSnapshot.syncSpace.invitation.expiresAtMs, $effectiveLocale),
                  },
                )}
              </p>
              <div class="confirmation-code">
                <span>{text($effectiveLocale, "pairing.code")}</span>
                <strong>{$shellSnapshot.syncSpace.invitation.confirmationCode}</strong>
              </div>
              <div class="invitation-qr" aria-label={text($effectiveLocale, "pairing.qrLabel")}>
                {@html $shellSnapshot.syncSpace.invitation.qrSvg}
                <span>{text($effectiveLocale, "pairing.qrHint")}</span>
                <button
                  class="invitation-qr-expand"
                  type="button"
                  on:click={() => (qrExpanded = true)}
                >{text($effectiveLocale, "pairing.enlarge")}</button>
              </div>
              <button
                class="secondary-action invitation-copy"
                type="button"
                disabled={$shellSnapshot.syncSpace.state === "copyingInvitation"}
                on:click={() =>
                  shellSnapshot.copyPairingInvitation(
                    $shellSnapshot.syncSpace.invitation?.invitationId ?? "",
                  )}
              >
                <span aria-hidden="true">⧉</span>
                <strong>
                  {$shellSnapshot.syncSpace.state === "copyingInvitation"
                    ? text($effectiveLocale, "pairing.copying")
                    : text($effectiveLocale, "pairing.copy")}
                </strong>
                <em>{text($effectiveLocale, "pairing.safe")}</em>
              </button>
              {#if $shellSnapshot.syncSpace.invitationCopiedAtMs !== null}
                <p class="copy-hint">
                  {text($effectiveLocale, "pairing.copiedAt", { time: formatTime($shellSnapshot.syncSpace.invitationCopiedAtMs, $effectiveLocale) })}
                </p>
              {/if}
              <p>
                {text($effectiveLocale, "pairing.issuer", {
                  name: $shellSnapshot.syncSpace.invitation.issuerDeviceName,
                  fingerprint: $shellSnapshot.syncSpace.invitation.issuerShortFingerprint
                })}
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
              space.id === device.spaceId && canManageSyncSpace(space.localRole, "remove"))}
        />
      </div>
      {:else}
        <p class="advanced-intro">{text($effectiveLocale, "advanced.intro")}</p>

        <HmacDiagnosticCard
          state={$shellSnapshot.syncSpace.state}
          diagnostic={$shellSnapshot.syncSpace.hmacDiagnostic}
          onRun={() => shellSnapshot.runSpaceHmacDiagnostic()}
        />

        <StatusCard
          state={$shellSnapshot.connection.state}
          title={formatUiMessage($effectiveLocale, $shellSnapshot.connection.title)}
          description={formatUiMessage($effectiveLocale, $shellSnapshot.connection.description)}
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
        aria-label={text($effectiveLocale, "pairing.closeExpanded")}
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
            <h2 id="qr-dialog-title">{text($effectiveLocale, "pairing.scanTitle")}</h2>
            <p id="qr-dialog-description">{text($effectiveLocale, "pairing.scanHint")}</p>
          </div>
          <button
            class="qr-dialog-close"
            type="button"
            aria-label={text($effectiveLocale, "pairing.closeExpanded")}
            on:click={() => (qrExpanded = false)}
          >×</button>
        </header>
        <div class="expanded-invitation-qr" aria-label={text($effectiveLocale, "pairing.expandedQrLabel")}>
          {@html $shellSnapshot.syncSpace.invitation.qrSvg}
        </div>
        <div class="qr-dialog-confirmation">
          <span>{text($effectiveLocale, "pairing.code")}</span>
          <strong>{$shellSnapshot.syncSpace.invitation.confirmationCode}</strong>
        </div>
        <p class="qr-dialog-expiry">
          {text($effectiveLocale, "pairing.expiresAt", { time: formatTime($shellSnapshot.syncSpace.invitation.expiresAtMs, $effectiveLocale) })}
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
      {text($effectiveLocale, $settingsSnapshot.settings.syncEnabled ? "settings.syncEnabled" : "settings.syncPaused")}
    </button>
    </footer>
  {/if}
</main>
