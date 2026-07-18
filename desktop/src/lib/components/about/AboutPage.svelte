<script lang="ts">
  import { effectiveLocale, text } from "$lib/i18n";

  export let version: string;
  export let onBack: () => void = () => {};
</script>

<section class="about-page" aria-labelledby="about-title">
  <div class="about-toolbar">
    <button class="about-back" type="button" on:click={onBack} aria-label={text($effectiveLocale, "about.backLabel")}>
      <span aria-hidden="true">←</span>
      {text($effectiveLocale, "about.back")}
    </button>
  </div>

  <div class="about-hero">
    <img src="/app-icon.png" alt={text($effectiveLocale, "about.iconAlt")} />
    <div>
      <h2 id="about-title">{text($effectiveLocale, "app.title")}</h2>
      <p>EggClip · {text($effectiveLocale, "common.version", { version })}</p>
    </div>
  </div>

  <p class="about-summary">{text($effectiveLocale, "about.summary")}</p>

  <div class="about-details">
    <article>
      <span aria-hidden="true">⌁</span>
      <div>
        <strong>{text($effectiveLocale, "about.localTitle")}</strong>
        <p>{text($effectiveLocale, "about.localHint")}</p>
      </div>
    </article>
    <article>
      <span aria-hidden="true">Aa</span>
      <div>
        <strong>{text($effectiveLocale, "about.textTitle")}</strong>
        <p>{text($effectiveLocale, "about.textHint")}</p>
      </div>
    </article>
    <article>
      <span aria-hidden="true">⌾</span>
      <div>
        <strong>{text($effectiveLocale, "about.privacyTitle")}</strong>
        <p>{text($effectiveLocale, "about.privacyHint")}</p>
      </div>
    </article>
  </div>

  <p class="about-footer">{text($effectiveLocale, "about.footer")}</p>
</section>
