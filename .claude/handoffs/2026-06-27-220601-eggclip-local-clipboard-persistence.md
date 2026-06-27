# Handoff: EggClip local clipboard persistence boundary

## Session Metadata

- Created: 2026-06-27 22:06:01
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: about 35 minutes

### Recent Commits (for context)

- 2b43849 feat: 实现本地剪贴板持久化边界，生成不可变ClipboardItem并同事务提交
- 1c4c22b feat: 实现本地设备身份持久化存储（deviceId 和 originSeq）
- e391e01 feat: 实现剪贴板历史记录保留策略（过期清理、数量限制、清空历史）
- 755871e feat: 实现桌面端和鸿蒙端仓库基础CRUD
- 14c2401 feat: 实现桌面端SQLite存储层及鸿蒙端Schema迁移定义

## Handoff Chain

- **Continues from**: [2026-06-27-195423-eggclip-authenticated-transport-session.md](./2026-06-27-195423-eggclip-authenticated-transport-session.md)
  - Previous title: EggClip authenticated transport session integration
- **Supersedes**: None

Review the previous handoff for authenticated transport/session context before extending sync integration.

## Current State Summary

This session continued the D2 storage/sync-engine plan. The completed work establishes the first local clipboard persistence boundary on both platforms: local text is converted into an immutable `ClipboardItem`, stored as encrypted content metadata/bytes, and tied to monotonic `originSeq` progression. The desktop side now has a real SQLite transaction workflow; the Harmony side has a command-plan equivalent that still needs a real `relationalStore` transaction runner. The repository is clean except for this new handoff file, and the latest functional changes are already represented by commit `2b43849`.

## Codebase Understanding

## Architecture Overview

EggClip is moving through D2 model/storage before connecting full sync. The desktop Rust backend owns durable storage, identity metadata and local persistence workflows. Svelte remains outside SQLite and system clipboard internals. Harmony currently mirrors the domain and repository command shape in ArkTS, but most persistence is still SQL command generation rather than executed RDB transactions. Both sides intentionally keep network broadcast separate from local transaction success so failed network delivery cannot roll back local copy history or sequence allocation.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `AGENTS.md` | Product, architecture, safety and validation rules | Must be read before continuing; contains v1 boundaries and logging/security constraints |
| `docs/EggClip最佳实现方案.md` | Product/architecture decision source | Higher priority than platform TODO files when plans conflict |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop phased plan | D2 Sync Engine now has local `ClipboardItem` conversion checked |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony phased plan | Notes that local clipboard command planning is done but real RDB runner remains |
| `desktop/src-tauri/src/storage/repositories.rs` | Desktop repository layer plus local persistence workflow | Contains `persist_local_clipboard_text` and tests for transaction success/rollback |
| `desktop/src-tauri/src/sync/mod.rs` | Shared desktop sync domain models/builders | Provides `build_local_clipboard_item`, HLC, settings validation and content digest helpers |
| `harmony/entry/src/main/ets/data/repositories/RepositoryCommands.ets` | Harmony repository SQL command layer | Contains `LocalClipboardPersistenceCommands` command-plan workflow |
| `harmony/entry/src/test/LocalUnit.test.ets` | Harmony local unit tests | Covers repository commands and the new local clipboard persistence command plan |

## Key Patterns Discovered

- Desktop storage workflows should stay in Rust and expose small, explicit boundaries. UI and Tauri commands should call services rather than assemble SQL or domain logic.
- Clipboard plaintext can exist transiently in memory while building a local event, but storage rows must persist `encrypted_content`; loaded `ClipboardItemRecord` values intentionally return `plaintext: None`.
- `originSeq` must advance only as part of successful local persistence. Desktop now enforces rollback when the item insert fails.
- Harmony code currently separates repository intent from execution with `RepositoryCommand`. New persistence behavior should either follow that command-plan style or introduce a real runner in `data/db/` before marking full repository persistence done.
- Network broadcasting is explicitly deferred until after local transaction success. Do not put transport send calls into the database transaction path.

## Work Completed

## Tasks Finished

- [x] Added desktop `persist_local_clipboard_text` workflow in `desktop/src-tauri/src/storage/repositories.rs`.
- [x] Desktop workflow now builds immutable `ClipboardItem` with UUID v7 item id, HLC, local device id, HMAC digest and monotonic `originSeq`.
- [x] Desktop workflow writes `encrypted_content`, `received_at` and `expires_at` in one SQLite transaction.
- [x] Desktop transaction rollback test verifies failed item insert does not advance `nextOriginSeq`.
- [x] Added Harmony `LocalClipboardPersistenceCommands` to build a local persistence command plan.
- [x] Added Harmony unit coverage for generated commands, plaintext exclusion from SQL and invalid text rejection.
- [x] Updated desktop and Harmony development TODO documents to reflect completed command/workflow boundaries.

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Checked local copy to immutable `ClipboardItem`; added subtask for local transaction boundary | Keeps TODO status aligned with implemented desktop behavior |
| `HARMONY_DEVELOPMENT_TODO.md` | Added checked subtask for local clipboard persistence command plan | Makes clear what is done versus still pending on Harmony |
| `desktop/src-tauri/src/storage/repositories.rs` | Added local clipboard persistence input/result types, transactional workflow helpers, expiry calculation and tests | Provides concrete desktop storage boundary needed before sync broadcast |
| `harmony/entry/src/main/ets/data/repositories/RepositoryCommands.ets` | Added command-plan input/result and `LocalClipboardPersistenceCommands` | Mirrors desktop workflow shape without pretending real RDB execution exists |
| `harmony/entry/src/test/LocalUnit.test.ets` | Added unit test for local clipboard persistence command plan | Guards generated SQL and command order |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Keep broadcast out of local persistence | Send inside transaction, send immediately before transaction, or return persisted item for later send | Local copy must never wait on network; network failure must not roll back local record |
| Desktop workflow takes `encrypted_content` as input | Store plaintext temporarily, invent placeholder encryption, or require encrypted bytes from caller | Avoids pretending encryption exists while preserving “DB stores encrypted content only” invariant |
| Put desktop workflow in the desktop storage repository file for now | Create a new service module immediately or keep near repository helpers | Current needed helpers are private in the same file; later refactor can move to a dedicated local clipboard storage service once boundaries grow |
| Harmony adds command-plan workflow only | Implement full `relationalStore` runner now or stay with command layer | The existing Harmony D2 work is command-layer only; this keeps scope small and honest |
| `originSeq` rollback is enforced on desktop | Allocate sequence before insert in a separate call or allocate inside same transaction | Failed local persistence should not consume sequence numbers |

## Pending Work

## Immediate Next Steps

1. Implement Harmony real `relationalStore` transaction runner in `harmony/entry/src/main/ets/data/db/`, then execute `SCHEMA_MIGRATIONS` and `RepositoryCommand` arrays transactionally.
2. Refactor or wrap desktop `persist_local_clipboard_text` behind a sync/storage service that can be called from the actual clipboard listener path without UI coupling.
3. Add the post-commit broadcast boundary: after local transaction success, enqueue/send authenticated `ITEM_LIVE`; network failure should surface status but not roll back local record.

## Blockers/Open Questions

- [ ] Harmony real RDB execution is not implemented yet. Needed to mark full repository persistence and local identity persistence done.
- [ ] Content encryption pipeline is not wired into either platform’s local clipboard persistence caller. Current workflows accept `encrypted_content` bytes rather than producing them.
- [ ] Desktop local clipboard listener is not yet connected to the new persistence workflow.
- [ ] Authenticated `ITEM_LIVE` broadcast path needs integration with existing protocol/session code.

## Deferred Items

- Retention-on-insert behavior is deferred. Current desktop local persistence writes the item and expiry, but does not immediately run retention cleanup in the same call.
- HLC state persistence beyond `HlcTimestamp::new(now_ms, 0)` for local inserts is deferred until the sync coordinator owns local/remote clock observation.
- Harmony random device id generation is still not real; only command construction exists.

## Context for Resuming Agent

## Important Context

The repo is on `main`. Latest functional work is already committed as `2b43849`; only this handoff file should be untracked/modified after creation. Do not re-implement the just-finished local persistence boundary. Continue from the TODO plans and AGENTS constraints. Desktop now has a real SQLite transaction path in `persist_local_clipboard_text`; Harmony only has SQL command planning. The correct next architectural move is either the Harmony RDB transaction runner or connecting desktop clipboard events to the persistence workflow, then authenticated `ITEM_LIVE` post-commit broadcast.

Do not log clipboard text, content digest, invite secrets, keys or full frames. Do not add cloud, account, telemetry, auto-update or public relay behavior. Harmony must not silently read clipboard; any send-from-phone flow must remain PasteButton-driven.

## Assumptions Made

- Latest commit `2b43849` is accepted as the durable state of this session’s functional changes.
- For desktop tests, caller-provided `encrypted_content` stands in for a future encryption layer; this is intentional and should not be treated as real encryption.
- `expires_at` is derived from `now_ms + retentionDays * 24h` using current settings validation.
- Harmony `LocalClipboardPersistenceCommands` is a deterministic command builder, not a persistence guarantee.

## Potential Gotchas

- The scaffold script may fail under Windows GBK when git output includes non-ASCII text. Running it with `PYTHONUTF8=1` fixed this session.
- `harmony/build-profile.json5` may include local signing configuration. Do not print or copy protected material from that file.
- Harmony `assembleHap` currently warns about missing signingConfig and Pasteboard permission use; these were present/expected in recent validation.
- Desktop `persist_local_clipboard_text` requires a valid local device row in `devices` for the current space; otherwise the foreign key fails and the transaction rolls back.
- Do not mark Harmony full repository implementation done until `relationalStore` execution exists and is tested.

## Environment State

## Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Python with `PYTHONUTF8` enabled for the handoff scaffold due Windows Unicode output
- Rust/Cargo in `desktop/src-tauri`
- pnpm/SvelteKit/Vitest in `desktop`
- DevEco hvigor from `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`

## Active Processes

- No dev server, watcher or simulator process was intentionally left running by this session.

## Environment Variables

- `PYTHONUTF8`
- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`

## Validation Performed

- `cd D:\Develop\eggclip\desktop && pnpm check` passed
- `cd D:\Develop\eggclip\desktop && pnpm test` passed
- `cd D:\Develop\eggclip\desktop && pnpm build` passed
- `cd D:\Develop\eggclip\desktop\src-tauri && cargo fmt -- --check` passed
- `cd D:\Develop\eggclip\desktop\src-tauri && cargo check` passed
- `cd D:\Develop\eggclip\desktop\src-tauri && cargo test` passed with 73 tests
- `cd D:\Develop\eggclip\harmony && hvigorw.bat test --no-daemon` passed
- `cd D:\Develop\eggclip\harmony && hvigorw.bat assembleHap --no-daemon` passed

Known validation warnings:

- Harmony static Pasteboard API warning for `ohos.permission.READ_PASTEBOARD`
- Harmony `No signingConfig found for product default`

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`
- `desktop/src-tauri/src/storage/repositories.rs`
- `desktop/src-tauri/src/sync/mod.rs`
- `harmony/entry/src/main/ets/data/repositories/RepositoryCommands.ets`
- `harmony/entry/src/test/LocalUnit.test.ets`

---

Security check reminder: this document should contain no clipboard samples from a real user, no keys, no invitation secrets, no signing material and no protected build-profile material.
