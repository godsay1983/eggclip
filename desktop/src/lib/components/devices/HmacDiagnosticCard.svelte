<script lang="ts">
  import { effectiveLocale, text } from "$lib/i18n";
  import type { SpaceHmacDiagnosticSummary, SyncSpaceState } from "$lib/types/shell";

  export let state: SyncSpaceState["state"] = "idle";
  export let diagnostic: SpaceHmacDiagnosticSummary | null = null;
  export let onRun: () => Promise<void> | void = () => {};
</script>

<section class="poc-connect-card" aria-label={text($effectiveLocale, "diagnostic.keyLabel")}>
  <div class="section-heading compact">
    <div>
      <span class="eyebrow">{text($effectiveLocale, "diagnostic.eyebrow")}</span>
      <h2>{text($effectiveLocale, "diagnostic.hmacTitle")}</h2>
    </div>
  </div>

  <p>{text($effectiveLocale, "diagnostic.hmacHint")}</p>
  {#if diagnostic}
    <div class="confirmation-code">
      <span>{text($effectiveLocale, "diagnostic.sixDigit")}</span>
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
    {text($effectiveLocale, state === "loading" ? "diagnostic.running" : "diagnostic.generate")}
  </button>
</section>
