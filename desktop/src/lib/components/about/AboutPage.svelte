<script lang="ts">
  export let version: string;
  export let onBack: () => void = () => {};
</script>

<section class="about-page" aria-labelledby="about-title">
  <div class="about-toolbar">
    <button class="about-back" type="button" on:click={onBack} aria-label="返回剪贴板首页">
      <span aria-hidden="true">←</span>
      返回
    </button>
  </div>

  <div class="about-hero">
    <img src="/app-icon.png" alt="蛋定 Clip 图标" />
    <div>
      <h2 id="about-title">蛋定 Clip</h2>
      <p>EggClip · 版本 {version}</p>
    </div>
  </div>

  <p class="about-summary">纯局域网剪贴板同步，让 Windows 与 HarmonyOS 之间传递文本更轻松。</p>

  <div class="about-details">
    <article>
      <span aria-hidden="true">⌁</span>
      <div>
        <strong>只在局域网运行</strong>
        <p>不需要账号、云服务器或公网中继，设备通过加密连接同步。</p>
      </div>
    </article>
    <article>
      <span aria-hidden="true">Aa</span>
      <div>
        <strong>专注纯文本</strong>
        <p>当前版本同步 text/plain，单条内容最大 256 KiB。</p>
      </div>
    </article>
    <article>
      <span aria-hidden="true">⌾</span>
      <div>
        <strong>隐私保存在本机</strong>
        <p>历史、设备身份和同步设置均由本机管理。</p>
      </div>
    </article>
  </div>

  <p class="about-footer">EggClip 1.0 · 为 Windows 与 HarmonyOS 设计</p>
</section>
