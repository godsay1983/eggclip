# Handoff: EggClip local history capture

## Session Metadata

- Created: 2026-06-28 19:32:05
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: about 1 hour for local-history capture wiring, validation, and handoff capture
- Git state at handoff creation: `main...origin/main`; no code changes pending, only this handoff document is untracked

### Recent Commits (for context)

- `cfd3b92 feat: 接入本地剪贴板历史持久化，桌面端和鸿蒙端读取剪贴板时写入本机历史并刷新UI`
- `d5e11ee feat: 添加单条历史记录删除功能`
- `d75c187 docs: 更新历史元数据预览交接文档`
- `78b17b4 docs: 添加交接文档模板`
- `9a43454 feat: 添加最近5条历史记录元数据预览`

## Handoff Chain

- **Continues from**: [2026-06-28-174850-eggclip-history-metadata-preview.md](./2026-06-28-174850-eggclip-history-metadata-preview.md)
  - Previous title: EggClip history metadata preview
- **Supersedes**: None; this handoff adds the post-preview local capture slice.

## Current State Summary

EggClip has completed the next local history slice after metadata preview and single-item delete. The latest committed state wires user-visible clipboard operations into local history persistence on both desktop and HarmonyOS: desktop manual read and Windows clipboard monitor events now create local history records, and HarmonyOS PasteButton read success now creates a local RDB history record before continuing the existing POC send path. The history UI still shows metadata only, not clipboard body text. All desktop and Harmony validation commands required for this slice passed.

## Important Context

- Latest functional commit is `cfd3b92 feat: 接入本地剪贴板历史持久化，桌面端和鸿蒙端读取剪贴板时写入本机历史并刷新UI`.
- Worktree state at handoff creation is clean except for `.claude/handoffs/2026-06-28-193205-eggclip-local-history-capture.md`.
- This slice makes history visible after real user operations, but it is still metadata-only. Do not expose `encrypted_content`, `content_digest`, raw HMAC material, clipboard plaintext logs, keys, or invites in UI/logs/docs.
- Desktop uses a local history bootstrap space/device in the history command layer, not in the generic repository function. This is intentional: generic `persist_local_clipboard_text` must still fail when required space/device FK rows are absent, preserving transaction-boundary tests.
- Desktop local capture uses `LOCAL_HISTORY_ENCRYPTED_PLACEHOLDER` as the stored encrypted blob for the current metadata-only bridge. It deliberately does not store plaintext body bytes for display.
- Harmony `HistoryStore.captureLocalText` uses `LocalClipboardPersistenceService`, but the `contentDigest` is currently a UUID-derived local transition value. The formal HMAC path must wait for CryptoFramework/HUKS integration.
- Harmony PasteButton capture does not block POC sending. `HomePage.captureLocalHistoryText()` runs asynchronously and updates the recent-history card status/list when finished.
- Known Harmony warnings remain expected: Pasteboard permission warning, many RDB "Function may throw exceptions" warnings, and no signingConfig.
- The handoff tooling should be run with `PYTHONUTF8=1` on this Windows machine if encoding issues appear.

## Immediate Next Steps

1. Decide the next TODO-driven slice. Recommended: implement history body access only after designing the plaintext/decryption path; otherwise continue with connection/sync protocol lifecycle work that does not require displaying stored bodies.
2. If continuing history UX, design a safe "copy from history" flow first: where plaintext comes from, how decryption keys are loaded, how errors are shown, and how to avoid logging bodies or digests.
3. If continuing sync, connect the existing post-commit local persistence boundary to formal `ITEM_LIVE` broadcast only after authenticated WebSocket session lifecycle is wired.
4. Before any Harmony crypto work, replace the UUID transition digest with real HMAC via CryptoFramework/HUKS and shared protocol vectors.

## Codebase Understanding

## Architecture Overview

Desktop history capture flows through Rust Tauri commands, then typed TypeScript API wrappers and Svelte stores. Components stay presentational. The Rust history command owns the local-history bootstrap because it is a UI-facing bridge before formal space/pairing exists. Harmony history capture flows from `HomePage` PasteButton success into `HistoryStore`, then `LocalClipboardPersistenceService`, repository commands, and RDB transaction execution. Pages do not directly manipulate RDB.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/src-tauri/src/history.rs` | Tauri history commands and safe DTOs | Adds `capture_clipboard_history_text`, local history bootstrap, retention, and regression test |
| `desktop/src-tauri/src/lib.rs` | Tauri command registration | Exposes the capture command to the frontend |
| `desktop/src/lib/api/shell.ts` | Typed frontend API wrapper | Adds `captureClipboardHistoryText()` |
| `desktop/src/lib/stores/shell.ts` | Desktop shell orchestration | Persists manual read and monitor events into local history and refreshes the list |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Harmony history state | Adds `captureLocalText()` and bridges PasteButton text into persistence |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Harmony homepage UI | Calls local history capture after PasteButton read success |
| `harmony/entry/src/main/ets/services/sync/LocalClipboardPersistenceService.ets` | Local immutable item persistence service | Existing service now used by visible PasteButton path |
| `harmony/entry/src/main/ets/data/repositories/LocalIdentityRdbRepository.ets` | Local device ID and origin sequence repository | Fixed strict ArkTS `throw` type issue exposed by `assembleHap` |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop plan | Marks visible local clipboard operations as history-producing |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony plan | Marks PasteButton local item creation/history refresh complete |

## Key Patterns Discovered

- Keep desktop components away from raw `invoke`; put Tauri calls in `desktop/src/lib/api/` and orchestration in `desktop/src/lib/stores/`.
- Keep Harmony pages away from direct RDB calls; use store/service/repository boundaries.
- Generic persistence functions should not hide missing formal state by silently creating FK rows. Transitional bootstrap belongs at the specific command/store boundary that needs it.
- Recent history preview remains a metadata feature until key/decryption flow is implemented.
- Build output can be noisy on Harmony. Treat actual ArkTS compiler errors separately from known warnings.

## Work Completed

### Tasks Finished

- [x] Added desktop `capture_clipboard_history_text` Tauri command.
- [x] Added desktop TypeScript API wrapper `captureClipboardHistoryText()`.
- [x] Updated desktop shell store so manual clipboard reads persist local history and refresh recent metadata.
- [x] Updated desktop clipboard monitor event flow so observed local text persists local history without blocking the UI event path.
- [x] Added local-history space/device bootstrap at the desktop history command boundary.
- [x] Added Rust regression test proving visible local capture creates a history record and does not store plaintext as the encrypted blob.
- [x] Updated Harmony `HistoryStore` with `captureLocalText()`.
- [x] Updated Harmony `HomePage` so PasteButton read success creates local history and refreshes recent metadata.
- [x] Fixed ArkTS strict throw issue in `LocalIdentityRdbRepository` found during `assembleHap`.
- [x] Updated both TODO documents to reflect the completed local-history capture slice and remaining plaintext/decryption work.

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Marked desktop read/monitor history persistence complete | Keep development plan aligned with actual behavior |
| `HARMONY_DEVELOPMENT_TODO.md` | Marked PasteButton local item creation/history refresh complete and noted temporary digest | Keep mobile plan aligned and document security gap |
| `desktop/src-tauri/src/history.rs` | Added capture command, local bootstrap, retention call, and regression test | Make visible desktop clipboard operations create metadata-only local history |
| `desktop/src-tauri/src/lib.rs` | Registered capture command | Expose backend command to frontend |
| `desktop/src/lib/api/shell.ts` | Added typed capture API wrapper | Preserve frontend API boundary |
| `desktop/src/lib/stores/shell.ts` | Captures manual reads and monitor events into local history, refreshes recent list, improves status text | Make desktop history visible after actual operations |
| `harmony/entry/src/main/ets/data/repositories/LocalIdentityRdbRepository.ets` | Wrapped non-`Error` catch values before rethrow | Satisfy ArkTS compiler and preserve rollback behavior |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Calls local-history capture after PasteButton read success | Make mobile history visible after real user-authorized reads |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Added persistence service bridge and local capture snapshot refresh | Keep page free of RDB details |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Capture visible operations into local history now, but keep metadata-only UI | Wait for full crypto/decryption, or show plaintext directly | User wanted visible progress; metadata-only avoids privacy regression and plaintext exposure |
| Put desktop local-history bootstrap in `history.rs` command layer | Put bootstrap inside generic repository, or require formal paired space first | Repository must retain strict FK/transaction semantics; command-layer bridge is safer until formal pairing exists |
| Use placeholder encrypted content for desktop local history bridge | Store plaintext, store empty blob, or use placeholder | Placeholder proves no plaintext body is stored for preview while keeping required DB field populated |
| Use temporary UUID-derived Harmony digest | Block Harmony history capture until HMAC, or invent custom crypto | Allows local RDB flow to be visible while explicitly documenting that formal HMAC awaits CryptoFramework/HUKS |
| Let Harmony capture and POC send run independently | Block send until local history capture finishes, or skip history on send | Local clipboard operation should not wait on network; current POC send behavior remains responsive |

## Pending Work

### Blockers/Open Questions

- [ ] History body preview/copy requires a formal plaintext/decryption strategy. Need to decide whether bodies are shown by default, on explicit expansion, or copy-only.
- [ ] Harmony local digest is transitional. Needs replacement with real HMAC once CryptoFramework/HUKS path is implemented.
- [ ] Formal `ITEM_LIVE` broadcast is still not connected to authenticated WebSocket lifecycle.
- [ ] Desktop and Harmony local history use a fixed local-history space bridge before formal pairing/space selection exists. This should be revisited when pairing creates real spaces.

### Deferred Items

- History body preview and copy: deferred because safe decryption/key-loading UX is not implemented.
- Formal HMAC on Harmony: deferred to HUKS/CryptoFramework work.
- Post-commit broadcast to real peers: deferred until authenticated session lifecycle and `ITEM_LIVE` path are wired.
- Cross-device batch history and sync heads: deferred until formal connection manager/sync lifecycle.

## Context for Resuming Agent

## Assumptions Made

- v1 scope remains text/plain only, max 256 KiB per plaintext item, LAN-only, no cloud/account/server.
- Showing content length, source short ID, and timestamps is acceptable; showing body/digest/encrypted bytes is not.
- `cfd3b92` is the authoritative latest functional commit for the local-history capture slice.
- The user values TODO-driven incremental progress and expects TODO checkboxes to be updated when functionality is genuinely usable.

## Potential Gotchas

- Do not move the desktop bootstrap back into `persist_local_clipboard_text`; that breaks the intentional FK-failure rollback test.
- Do not claim current Harmony `contentDigest` is secure HMAC. It is a transition value documented in TODO.
- `encrypted_content` currently uses a placeholder in desktop local capture and should not be displayed or copied as body content.
- Desktop monitor persistence is intentionally best-effort async; failures update connection/status state rather than blocking clipboard event handling.
- Harmony `PasteButton` must remain the real ArkUI security component. Do not replace it with a normal button.
- Harmony `hvigor assembleHap` may expose stricter ArkTS compiler checks than `hvigor test`.
- The branch state may change if the user commits this handoff. Re-check `git status -sb` before continuing work.

## Environment State

### Tools/Services Used

- PowerShell on Windows.
- Node/pnpm in `D:\Develop\eggclip\desktop`.
- Rust/Cargo in `D:\Develop\eggclip\desktop\src-tauri`.
- DevEco hvigor via `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`.
- Session handoff skill scripts from `C:\Users\caozhipeng\.agents\skills\session-handoff`.

### Active Processes

- No dev servers, watchers, or background validation processes were intentionally left running by this handoff.

### Environment Variables

- `PYTHONUTF8` for handoff tooling.
- `JAVA_HOME`, `DEVECO_SDK_HOME`, and `Path` for Harmony validation.

## Verification Completed

- Desktop frontend: `pnpm check` passed.
- Desktop frontend tests/build: `pnpm test` and `pnpm build` passed.
- Desktop Rust: `cargo fmt -- --check`, `cargo check`, and `cargo test` passed.
- Rust test count at validation time: 85 passed.
- HarmonyOS: `hvigorw.bat test --no-daemon` passed with known warnings.
- HarmonyOS: `hvigorw.bat assembleHap --no-daemon` passed with known warnings.

## Related Resources

- [Previous handoff: history metadata preview](./2026-06-28-174850-eggclip-history-metadata-preview.md)
- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`

---

Security check note: no secrets, clipboard plaintext samples, HMAC digests, invitations, keys, certificate material, or signing `material` fields are included in this handoff.
