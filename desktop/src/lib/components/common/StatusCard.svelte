<script lang="ts">
  import { effectiveLocale, text } from "$lib/i18n";
  import StatusDot from "$lib/components/common/StatusDot.svelte";
  import type { ConnectionState } from "$lib/types/shell";

  export let state: ConnectionState = "offline";
  export let title = "";
  export let description = "";

  $: statusLabel =
    state === "online"
      ? text($effectiveLocale, "status.online")
      : state === "connecting"
        ? text($effectiveLocale, "status.connecting")
        : state === "authFailed"
          ? text($effectiveLocale, "status.authFailed")
          : state === "paused"
            ? text($effectiveLocale, "status.paused")
            : text($effectiveLocale, "status.offline");
</script>

<section class="status-card" aria-label={text($effectiveLocale, "status.connection")}>
  <div class="status-icon">
    <StatusDot {state} />
  </div>
  <div class="status-copy">
    <strong>{title}</strong>
    <p>{description}</p>
  </div>
  <span
    class:online={state === "online"}
    class:connecting={state === "connecting"}
    class:auth-failed={state === "authFailed"}
    class:paused={state === "paused"}
    class="status-label"
  >
    {statusLabel}
  </span>
</section>
