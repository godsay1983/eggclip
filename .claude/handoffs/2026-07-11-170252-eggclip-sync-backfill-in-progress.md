# Handoff: EggClip 可信重连完成与断线补同步进行中

## Session Metadata

- Created: 2026-07-11 17:02:52
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: long-running continuation

### Recent Commits (for context)

- `f0986f3` storage range query foundation
- `90bdd45` local clipboard content decryption helper
- `c0b5eb6` REQUEST_RANGE serialization fix
- `114981d` Harmony missing-range request sender
- `5fbdb1b` Harmony local sequence summary query

## Handoff Chain

- **Continues from**: [2026-07-11-133821-eggclip-formal-sync-and-todo-rebaseline.md](./2026-07-11-133821-eggclip-formal-sync-and-todo-rebaseline.md)
- **Supersedes**: None

## Current State Summary

Harmony H5 trusted-device connection lifecycle and desktop D4 ConnectionManager were verified by the user on real devices and their existing TODO checkboxes were marked complete. The current unfinished shared task is offline history backfill: desktop sends encrypted SYNC_HEADS after authentication; Harmony validates and persists them, compares local history, and sends encrypted REQUEST_RANGE. The desktop REQUEST_RANGE handler, ITEM_BATCH sender, Harmony ITEM_BATCH history persistence, ACK, retention-gap response, and complete dual-device acceptance are not implemented yet. Do not mark the two backfill TODO checkboxes until the entire chain is verified.

## Codebase Understanding

### Architecture Overview

- Desktop is the WebSocket listener and owns the trusted pairing server path in `desktop/src-tauri/src/transport/mod.rs`.
- Harmony initiates foreground trusted reconnect through `PairingConnectionStore.ets`.
- Database content is encrypted at rest with the space key; authenticated WebSocket business frames apply separate session AEAD. Never send stored database ciphertext directly.
- ITEM_LIVE and ITEM_BATCH must stay separate: batch history must never write the desktop/Harmony system clipboard.

### Critical Files

| File | Purpose | Relevance |
|---|---|---|
| `desktop/src-tauri/src/transport/mod.rs` | WebSocket pairing, authenticated session, SYNC_HEADS send | Implement REQUEST_RANGE and ITEM_BATCH sender here |
| `desktop/src-tauri/src/storage/repositories.rs` | Clipboard history queries | Has `summarize_available_sequences` and `list_by_origin_range` foundations |
| `desktop/src-tauri/src/protocol/mod.rs` | Rust protocol types | Has RequestRangePayload validation |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Trusted lifecycle and sync frame routing | Sends REQUEST_RANGE and persists remote SYNC_HEADS |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | ArkTS RDB gateways | Has local sequence summary query |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | ArkTS protocol parser | Has REQUEST_RANGE parser |
| `protocol/v1.schema.json` | Shared protocol schema | Has requestRangePayload schema |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop fixed TODO | D4 backfill line remains unchecked |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony fixed TODO | H5 backfill line remains unchecked |

### Key Patterns Discovered

- Use `apply_patch` for edits. Do not add TODO bullets; only check existing completed lines.
- Harmony ArkTS forbids implicit/untyped object literals. Create declared interfaces and use `JSON.parse(JSON.stringify(value)) as JsonObject` when converting a typed payload to generic JsonObject for the transport API.
- Rust storage must not return temporary query results as the final expression if a statement borrow survives; assign `collect()` to a local first.
- On Windows run Harmony scripts with `PYTHONUTF8=1` when using handoff scripts.

## Work Completed

### Tasks Finished

- [x] Harmony H5 trusted connection lifecycle, foreground recovery, single connection, WebSocket heartbeat and reconnect; user confirmed real-device test.
- [x] Desktop D4 ConnectionManager lifecycle boundary; user confirmed dual-device recovery test.
- [x] Desktop encrypted SYNC_HEADS sending and Harmony SYNC_HEADS validation/persistence foundation.
- [x] Shared REQUEST_RANGE schema and Rust/ArkTS type/parser foundations.

### Files Modified

| File | Changes | Rationale |
|---|---|---|
| `desktop/src-tauri/src/transport/mod.rs` | Trusted reconnect, session dedupe/state, heartbeat, SYNC_HEADS send, at-rest decrypt helper | Trusted lifecycle and safe backfill foundation |
| `desktop/src-tauri/src/storage/repositories.rs` | Sequence summary and range queries | Feed sync heads and requested history |
| `desktop/src-tauri/src/protocol/mod.rs` | RequestRange types and validation | Shared Rust protocol boundary |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Trusted lifecycle, SYNC_HEADS receive and REQUEST_RANGE send | Harmony sync orchestration |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | Trusted endpoint persistence and local sequence summary | Reconnect and range comparison |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | REQUEST_RANGE parser | ArkTS protocol boundary |
| `protocol/v1.schema.json` | requestRangePayload schema | Shared protocol contract |

### Decisions Made

| Decision | Options Considered | Rationale |
|---|---|---|
| Use `ranges: [{ originDeviceId, fromSeq, toSeq }]` for REQUEST_RANGE | Map or one range per frame | Explicit bounded ranges support multiple origins and schema validation |
| Re-encrypt batch content with the active session | Send RDB encrypted_content | RDB ciphertext is for at-rest protection and cannot be treated as transport ciphertext |
| Only mark TODOs after full user verification | Mark intermediate steps | User explicitly requires fixed TODO items to be checked only on full completion |

## Pending Work

## Immediate Next Steps

1. Implement desktop `REQUEST_RANGE` dispatch: parse/validate RequestRangePayload, verify current session space, load requested records with `list_by_origin_range`, decrypt valid local records with `decrypt_local_clipboard_content`, and return bounded encrypted ITEM_BATCH frames.
2. Define/update ITEM_BATCH and ACK payload parsing on both platforms; on Harmony persist batch entries through history-only path and send ACK.
3. Add an explicit retention-gap encrypted response for requests below minimumAvailable; add protocol tests and run desktop/Harmony builds.
4. Run paired desktop + Harmony real-device backfill test, then check exactly the existing D4/H5 backfill TODO lines.

### Blockers/Open Questions

- No external blocker. The scope is incomplete because ITEM_BATCH/ACK/gap handlers have not yet been implemented.

### Deferred Items

- Pending/reliable outbound queue is a separate H5 task and must not be merged into backfill work.

## Context for Resuming Agent

## Important Context

Do not claim the backfill task is complete yet. Earlier agents reported too many partial increments; the user now expects one whole TODO task to be completed before a final delivery. Continue the current shared D4/H5 backfill task end-to-end and only then update the existing checkboxes. Preserve all product boundaries in AGENTS.md: LAN only, text/plain only, 256 KiB per item, no secret/body logging, real-time vs history behavior separated.

### Assumptions Made

- Desktop remains the listener; Harmony is the foreground reconnect initiator.
- A batch has at most 100 items and at most 512 KiB plaintext total, per protocol README.
- A requested range below retention minimum must result in an explicit gap, not silent omission.

### Potential Gotchas

- Initial pairing queues AUTH_OK and SPACE_KEY_ROTATED before SYNC_HEADS. Keep that ordering; encrypted business frames cannot precede AUTH_OK.
- `encrypted_content` is local at-rest data and may include placeholders for remote history; only batch local entries that can be safely recovered.
- Harmony `JsonObject` is restrictive under ArkTS; use declared interfaces before serialization.
- Existing HUKS/DB warnings during Harmony builds predate this work. Treat new compiler errors as blockers.

## Environment State

### Tools/Services Used

- Desktop: `cargo fmt -- --check`, `cargo check`, `cargo test`.
- Harmony: `hvigorw.bat test --no-daemon`, `assembleHap --no-daemon` with JAVA_HOME and DEVECO_SDK_HOME configured.

### Active Processes

- No persistent server or build process was intentionally left running.

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `PYTHONUTF8`

## Related Resources

- [EggClip implementation plan](../../docs/EggClip最佳实现方案.md)
- [Protocol README](../../protocol/README.md)
- [Protocol schema](../../protocol/v1.schema.json)
- [Desktop TODO](../../DESKTOP_DEVELOPMENT_TODO.md)
- [Harmony TODO](../../HARMONY_DEVELOPMENT_TODO.md)

---

**Security Reminder**: No invitation, key, plaintext clipboard sample, credential, or signing material is recorded in this handoff.
