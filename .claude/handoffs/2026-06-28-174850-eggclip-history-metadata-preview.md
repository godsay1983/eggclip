# Handoff: EggClip history metadata preview

## Session Metadata

- Created: 2026-06-28 17:48:50
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: about 1.5 hours for the recent history metadata slice and handoff capture
- Git state at handoff creation: `main...origin/main [ahead 1]`

### Recent Commits (for context)

- `9a43454 feat: 添加最近5条历史记录元数据预览`
- `2f3c8b3 feat: 桌面端与鸿蒙端接入历史数量摘要读取`
- `e5580ba feat: 添加清空本机历史功能，支持桌面端和鸿蒙端`
- `cfa1cac docs: 添加EggClip UI polish和导航清理的交接文档`
- `b5ed2a4 refactor: 重构Tab图标为独立Glyph组件并调整样式`

## Handoff Chain

- **Continues from**: [2026-06-28-155336-eggclip-ui-polish.md](./2026-06-28-155336-eggclip-ui-polish.md)
  - Previous title: EggClip UI polish and navigation cleanup
- **Supersedes**: None; this handoff adds post-UI-polish history feature context.

## Current State Summary

EggClip has moved past UI polish into the local history feature slice. The latest committed state adds read-only recent history metadata previews on both desktop and HarmonyOS. The work deliberately shows only item metadata, not plaintext bodies or digests, because the formal key/decryption path for stored history content is not implemented yet. The repository is clean except for this new handoff document, and the branch is one commit ahead of `origin/main`.

## Important Context

- The latest functional commit is `9a43454 feat: 添加最近5条历史记录元数据预览`. It is already committed locally and includes both desktop and HarmonyOS changes.
- Current branch state is `main...origin/main [ahead 1]`; no code changes are uncommitted at handoff time except `.claude/handoffs/2026-06-28-174850-eggclip-history-metadata-preview.md`.
- The history list currently displays metadata only: content length, source device short ID, and received time. It does not decrypt or show clipboard body text.
- This metadata-only behavior is intentional. Do not “fix” it by reading `encrypted_content` as plaintext or exposing `content_digest`; doing so would violate the project privacy/security boundary.
- The next natural feature slice is history item actions: copy, delete single item, details expansion, and refresh coordination after clear/delete. Those require a safe plaintext/decryption strategy before showing or copying stored bodies.
- HarmonyOS warnings from `hvigor assembleHap` are known existing warnings: Pasteboard permission warning, RDB “Function may throw exceptions” warnings, and missing signingConfig. They did not block this handoff.

## Immediate Next Steps

1. Decide the next history slice: either implement single-item delete first because it does not require plaintext decryption, or design the plaintext/decryption path before adding copy/detail previews.
2. If implementing delete, add desktop command/API/store/UI for `mark_deleted` and Harmony `HistoryStore`/repository delete flow; refresh history list and count after deletion.
3. If implementing copy/detail, first define how stored `encrypted_content` will be decrypted without logging or exposing secrets, then update TODO and tests before UI work.

## Codebase Understanding

## Architecture Overview

Desktop history flows through Rust repositories and Tauri commands into typed Svelte APIs/stores. UI components render state only. HarmonyOS history flows through RDB command/repository classes into `HistoryStore`, then `HomePage` renders the snapshot. Both sides keep page/components away from raw SQL and avoid displaying sensitive clipboard internals.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/src-tauri/src/history.rs` | Tauri history commands and safe DTOs | Defines clear history, count, and recent metadata preview command |
| `desktop/src-tauri/src/storage/repositories.rs` | SQLite repository layer | Adds `list_recent_all` and existing clear/count/delete primitives |
| `desktop/src/lib/api/shell.ts` | Typed frontend API wrapper | Maps Tauri history DTOs into UI-friendly summaries |
| `desktop/src/lib/stores/shell.ts` | Desktop shell state orchestration | Loads count plus recent metadata list together |
| `desktop/src/lib/components/clipboard/HistoryList.svelte` | Desktop history UI | Renders recent metadata cards and clear-history action |
| `harmony/entry/src/main/ets/data/repositories/RepositoryCommands.ets` | ArkTS SQL command definitions | Adds `listRecentAll` query for active history metadata |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | Harmony RDB repository layer | Executes list/count/clear commands and maps records |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Harmony history state | Loads count, limit, and recent metadata previews |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Harmony homepage UI | Shows latest clipboard card and recent metadata list |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop plan | Records completed history count and metadata preview slices |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony plan | Records completed history count and metadata preview slices |

## Key Patterns Discovered

- Desktop frontend should call `src/lib/api/*` wrappers, not Tauri `invoke` directly from components.
- Desktop Svelte stores should coordinate async loading and error states; components stay presentational.
- Rust command files should return UI-safe DTOs and avoid exposing database internals such as `content_digest`.
- Harmony pages should compose state and UI only; RDB access belongs in `data/repositories` and store orchestration belongs in `store`.
- For local history, `deleted_at IS NULL` is the active-record filter across both SQLite and Harmony RDB.

## Work Completed

### Tasks Finished

- [x] Added desktop Tauri command `list_clipboard_history_preview`.
- [x] Added desktop repository method `list_recent_all`.
- [x] Extended desktop shell types/API/store to carry recent history metadata items.
- [x] Updated desktop `HistoryList.svelte` to render recent metadata cards.
- [x] Added desktop CSS for history list cards.
- [x] Added Harmony repository command and RDB method `listRecentAll`.
- [x] Extended Harmony `HistoryStore` to load recent history metadata items.
- [x] Updated Harmony `HomePage` to render recent history metadata list.
- [x] Added/updated tests for initial shell state, Rust history command behavior, and ArkTS command SQL.
- [x] Updated both development TODO documents to mark the metadata preview slice complete and leave body preview/copy/delete pending.

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Marked recent 5 metadata list done; left body/copy/delete pending | Keep plan accurate |
| `HARMONY_DEVELOPMENT_TODO.md` | Marked Harmony metadata list done; left body/copy/delete pending | Keep plan accurate |
| `desktop/src-tauri/src/history.rs` | Added DTO and `list_clipboard_history_preview`; expanded test | Safe desktop history metadata command |
| `desktop/src-tauri/src/lib.rs` | Registered new Tauri command | Expose backend command to frontend |
| `desktop/src-tauri/src/storage/repositories.rs` | Added `list_recent_all` | Query active recent items without space filter for current shell |
| `desktop/src/app.css` | Added metadata card styles | Make list readable in existing EggClip style |
| `desktop/src/lib/api/shell.ts` | Added DTO mapping and API wrapper | Keep component/store away from raw invoke payloads |
| `desktop/src/lib/components/clipboard/HistoryList.svelte` | Render metadata list or empty state | Make history feature visible |
| `desktop/src/lib/shell.test.ts` | Assert initial history items are empty | Lock frontend state shape |
| `desktop/src/lib/stores/shell.ts` | Load count and metadata items together | Keep history summary consistent |
| `desktop/src/lib/types/shell.ts` | Added `HistoryItemSummary` | Type metadata item shape |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | Added `listRecentAll` | Execute recent active history query |
| `harmony/entry/src/main/ets/data/repositories/RepositoryCommands.ets` | Added `listRecentAll` SQL command | Keep SQL command layer explicit |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Render recent metadata items | Make history visible on homepage |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Added metadata item loading and formatting | Keep page free of RDB details |
| `harmony/entry/src/test/LocalUnit.test.ets` | Added `listRecentAll` SQL assertions | Guard command boundary |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Show metadata only for recent history | Show plaintext, show digest, show metadata | Plaintext decryption is not implemented and digest must not be exposed; metadata gives visible progress without privacy regression |
| Load latest 5 items | Load full configured history limit, load 5 | Small list is enough for homepage preview and avoids heavier UI/state before list actions are designed |
| Use all active items query for current shell | Require space filter, query all active records | Current shell does not yet have a full active-space selection flow; query still only returns local DB active records and hides deleted items |
| Keep copy/delete deferred | Implement all actions now, split into next slice | Copy requires plaintext/decryption design; delete deserves its own safe command and refresh path |

## Pending Work

### Blockers/Open Questions

- [ ] Stored body preview/copy needs a formal decryption path for `encrypted_content`; do not assume the blob is plaintext.
- [ ] Active space selection is still not fully surfaced in shell UI; current recent metadata preview queries all active local records.
- [ ] Need product decision on whether history detail view should show plaintext by default or require explicit user action.

### Deferred Items

- Single-item delete: safe to implement next because it can operate on `item_id` and `deleted_at` without plaintext.
- Copy stored history item: deferred until stored content decryption and UI permission flow are clear.
- History detail expansion: deferred until plaintext/decryption path and long-text UI are designed.
- Cross-page refresh after Settings clear: deferred; current homepage refreshes on appear/load, but not via a shared history invalidation event.

## Context for Resuming Agent

## Assumptions Made

- The current v1 scope remains text/plain only and LAN-only.
- Displaying metadata such as length and source device short ID is acceptable; displaying digest or encrypted bytes is not.
- The user wants incremental TODO-driven progress, not broad feature jumps.
- `9a43454` is the authoritative latest functional commit for the history metadata preview slice.

## Potential Gotchas

- `content_digest` is HMAC-derived and should still not be displayed in UI or ordinary logs.
- `encrypted_content` may be present but must not be treated as plaintext.
- Rust tests using hand-written HLC values must use the wire format like `0000018bcfe56800-0000`; decimal-looking timestamps fail the parser.
- Harmony build warnings are noisy; distinguish existing warnings from actual compiler errors.
- The handoff validator on this Windows machine should be run with `PYTHONUTF8=1` to avoid GBK decoding errors.

## Environment State

### Tools/Services Used

- PowerShell on Windows.
- Node/pnpm in `D:\Develop\eggclip\desktop`.
- Rust/Cargo in `D:\Develop\eggclip\desktop\src-tauri`.
- DevEco hvigor via `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`.
- Session handoff skill scripts from `C:\Users\caozhipeng\.agents\skills\session-handoff`.

### Active Processes

- No dev servers or long-running processes were intentionally left running by this handoff.

### Environment Variables

- `PYTHONUTF8` was used for handoff tooling.
- `JAVA_HOME`, `DEVECO_SDK_HOME`, and `Path` were set for Harmony validation.

## Verification Completed

- Desktop frontend: `pnpm check`, `pnpm test`, `pnpm build` passed.
- Desktop Rust: `cargo fmt -- --check`, `cargo check`, `cargo test` passed with 84 tests.
- HarmonyOS: `hvigor test --no-daemon` and `hvigor assembleHap --no-daemon` passed.
- Known Harmony warnings remained: Pasteboard permission warning, RDB exception warnings, and no signingConfig.

## Related Resources

- [Previous handoff: UI polish](./2026-06-28-155336-eggclip-ui-polish.md)
- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`

---

Security check note: no secrets, clipboard plaintext samples, HMAC digests, invitations, keys, or certificate material are included in this handoff.
