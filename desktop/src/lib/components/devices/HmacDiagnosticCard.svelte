<script lang="ts">
  import type { SpaceHmacDiagnosticSummary, SyncSpaceState } from "$lib/types/shell";

  export let state: SyncSpaceState["state"] = "idle";
  export let diagnostic: SpaceHmacDiagnosticSummary | null = null;
  export let onRun: () => Promise<void> | void = () => {};
</script>

<section class="poc-connect-card" aria-label="空间密钥诊断">
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">密钥诊断</span>
      <h2>跨端 HMAC 确认</h2>
    </div>
  </div>

  <p>两端确认码一致，表示当前同步空间密钥可正常使用。</p>
  {#if diagnostic}
    <div class="confirmation-code">
      <span>六位确认码</span>
      <strong>{diagnostic.confirmationCode}</strong>
    </div>
    <p>{diagnostic.spaceDisplayName}</p>
  {/if}
  <button
    class="secondary-action"
    type="button"
    disabled={state === "loading"}
    on:click={onRun}
  >
    {state === "loading" ? "诊断中…" : "生成确认码"}
  </button>
</section>
