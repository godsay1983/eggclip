<script lang="ts">
  const devices = [
    { name: "等待配对设备", state: "offline" },
  ];
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

  <section class="status-card" aria-label="连接状态">
    <span class="status-dot offline"></span>
    <div>
      <strong>等待配对设备</strong>
      <p>桌面端将在局域网中自动发现可信设备</p>
    </div>
  </section>

  <section class="clipboard-card">
    <div class="section-heading">
      <div>
        <span class="eyebrow">当前剪贴板</span>
        <h2>暂无同步内容</h2>
      </div>
      <span class="metadata">仅纯文本</span>
    </div>

    <p class="clipboard-placeholder">
      完成配对后，在线实时内容会自动写入桌面剪贴板；离线补齐的历史只会显示在列表中。
    </p>

    <button class="primary-action" type="button" disabled>复制此内容</button>
  </section>

  <section class="device-section">
    <div class="section-heading compact">
      <h2>设备</h2>
      <button class="text-button" type="button">添加设备</button>
    </div>
    <div class="device-list">
      {#each devices as device}
        <span class="device-chip">
          <span class:offline={device.state === "offline"} class="status-dot"></span>
          {device.name}
        </span>
      {/each}
    </div>
  </section>

  <section class="history-section">
    <div class="section-heading compact">
      <h2>最近记录</h2>
      <span class="metadata">0 / 50</span>
    </div>
    <div class="empty-state">
      <span aria-hidden="true">↔</span>
      <strong>复制后，内容会出现在这里</strong>
      <p>默认最多保存 50 条，最长保留 7 天。</p>
    </div>
  </section>

  <footer>
    <span>一步一点，不着急</span>
    <button class="sync-toggle" type="button">
      <span class="status-dot offline"></span>
      同步已开启
    </button>
  </footer>
</main>

