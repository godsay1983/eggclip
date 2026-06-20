<script lang="ts">
  import type { ConnectionState } from "$lib/types/shell";

  export let state: ConnectionState = "offline";
</script>

<span class:offline={state === "offline"} class:connecting={state === "connecting"} class:auth-failed={state === "authFailed"} class:paused={state === "paused"} class="status-dot"></span>
