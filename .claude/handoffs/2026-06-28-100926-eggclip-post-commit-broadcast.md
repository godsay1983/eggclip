# Handoff: EggClip post-commit local clipboard broadcast boundary

## Session Metadata
- Created: 2026-06-28 10:09:26
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: ~35 minutes

### Recent Commits (for context)
  - b8bc82f feat: 添加本地剪贴板事务后广播边界和失败回归测试
  - 8bbe931 feat: 实现同步暂停策略
  - c9786cc feat: 实现剪贴板去重逻辑，按itemId、来源序号和digest组合去重
  - 4c65244 feat: 实现入站剪贴板事件策略并接入本地持久化服务
  - 3494052 feat: 实现真实RDB仓库服务层，更新TODO和文档

## Handoff Chain

- **Continues from**: [2026-06-27-220601-eggclip-local-clipboard-persistence.md](./2026-06-27-220601-eggclip-local-clipboard-persistence.md)
  - Previous title: EggClip local clipboard persistence boundary
- **Supersedes**: None

> Review the previous handoff for full context before continuing storage or local clipboard persistence work.

## Current State Summary

The repo is on `main` and the working tree is clean at commit `b8bc82f feat: 添加本地剪贴板事务后广播边界和失败回归测试`. This session completed the next sync-engine boundary: local clipboard writes are persisted in a database transaction first, and only after a successful commit does the desktop service attempt a best-effort live broadcast. Broadcast failure is represented as status and does not roll back the committed local immutable item. Harmony now mirrors this boundary by returning a post-transaction broadcast scheduling status from `LocalClipboardPersistenceService`; real WebSocket sending remains deferred to the transport/pairing phase.

## Important Context

The next agent should treat this as a completed persistence and policy boundary, not completed cross-device sync. Real production broadcast still needs authenticated pairing/session integration and must not reuse plaintext POC transport. The intended flow is durable local commit first, then best-effort authenticated `ITEM_LIVE` broadcast if sync settings allow it; failures only become status and never undo local history.

## Immediate Next Steps

Start by reading `AGENTS.md`, this handoff and the previous linked handoff. Then choose the next TODO item deliberately: either connect the new desktop broadcaster seam to authenticated transport after session routing is ready, or finish Harmony H2 migration tests before expanding UI pages. Run the platform validation commands after any follow-up change.

## Codebase Understanding

### Architecture Overview

EggClip keeps storage, sync policy and transport intentionally separated. SQLite/RDB persistence owns durable immutable clipboard records and origin sequence advancement. Sync policy decides whether network work should happen after commit. Transport will later implement authenticated frame delivery but must not decide whether a local record should be persisted or rolled back. Harmony follows the same service layering: RDB transaction execution is in `data/`, orchestration is in `services/sync/`, and UI should consume service result state rather than touching RDB or WebSocket directly.

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `AGENTS.md` | Project rules and invariants | Must be read before new work; defines v1 scope, security constraints, validation commands and architecture boundaries. |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop phase plan | Sync Engine item for post-commit broadcast is now checked. Continue from remaining D3/D4 work. |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony phase plan | H2 storage/persistence is mostly complete; migration upgrade tests and page/theme tasks remain. |
| `desktop/src-tauri/src/sync/mod.rs` | Shared desktop sync domain/policy types | Added `LocalClipboardBroadcastOutcome`, `LocalClipboardBroadcaster` and `broadcast_local_clipboard_after_commit`. |
| `desktop/src-tauri/src/storage/repositories.rs` | Desktop SQLite repositories and local clipboard persistence | Added `persist_local_clipboard_text_then_broadcast` and rollback-safety tests. |
| `harmony/entry/src/main/ets/services/sync/LocalClipboardPersistenceService.ets` | Harmony local clipboard persistence orchestrator | Now returns `policy`, `broadcastStatus` and optional pause reason after transaction commit. |
| `protocol/README.md` | Protocol design and compatibility notes | Needed before real transport integration to avoid bypassing auth/session rules. |

### Key Patterns Discovered

- Storage transaction functions should remain deterministic and not perform network I/O.
- Network failures are reported as state/status and must not block local clipboard operations.
- Broadcast is best-effort and must happen after commit, never inside the SQLite/RDB transaction.
- Clipboard plaintext, secrets, keys, invites and full frames must not be logged or included in tests/handoffs.
- Harmony service result objects should expose explicit status for UI/store consumption, instead of requiring UI to infer behavior from exceptions.
- Tests use in-memory SQLite for desktop persistence boundaries and fake broadcasters for network-edge behavior.

## Work Completed

### Tasks Finished

- [x] Added desktop post-commit broadcast policy boundary.
- [x] Added desktop storage-level wrapper that persists local clipboard text first and broadcasts only after successful commit.
- [x] Added tests proving broadcast failure does not roll back the local record or origin sequence.
- [x] Added tests proving sync-disabled state skips broadcaster calls while still persisting locally.
- [x] Added Harmony post-transaction broadcast scheduling/skip status in `LocalClipboardPersistenceService`.
- [x] Updated desktop and Harmony TODO documents to reflect the completed boundary while keeping real WebSocket sending deferred.
- [x] Ran desktop and Harmony validation commands successfully.

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Marked post-commit broadcast boundary complete and added tested failure behavior note. | Keeps TODO aligned with implemented and verified behavior. |
| `HARMONY_DEVELOPMENT_TODO.md` | Clarified local persistence service now returns broadcast scheduling/skip status. | Avoids claiming real WebSocket broadcast is implemented. |
| `desktop/src-tauri/src/sync/mod.rs` | Added broadcaster trait, broadcast outcome type, post-commit broadcast helper and tests. | Establishes sync boundary independent of concrete transport. |
| `desktop/src-tauri/src/storage/repositories.rs` | Added `LocalClipboardPersistAndBroadcastResult`, post-commit wrapper and persistence/broadcast tests. | Proves network failure cannot roll back local history. |
| `harmony/entry/src/main/ets/services/sync/LocalClipboardPersistenceService.ets` | Added broadcast status enum and returned policy/status fields after transaction. | Gives mobile store/UI a stable contract for later transport integration. |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Introduce a broadcaster trait instead of wiring real transport now. | Implement real WebSocket send immediately; keep only a TODO; introduce a small trait boundary. | The protocol/authenticated transport path is not ready to be called from local persistence yet. A trait gives testable semantics without crossing phases. |
| Return `Failed` without carrying error details. | Store transport error string; log details; return a minimal enum. | Avoids accidental exposure of network frames or sensitive content and keeps failure handling policy-oriented. |
| Keep `persist_local_clipboard_text` pure storage and add a wrapper. | Modify the existing transaction function to broadcast; add wrapper after commit. | Preserves the existing storage boundary and makes the post-commit behavior explicit. |
| Harmony returns `SCHEDULED`/`SKIPPED`, not `FAILED`. | Add a failure status now; only expose scheduled/skipped until real sender exists. | There is no concrete mobile broadcaster yet, so failure would be misleading. |

## Pending Work

### Immediate Next Steps

1. Continue from TODO phase planning: choose between Harmony H2 migration upgrade tests or starting the real authenticated transport send path that consumes the new post-commit boundary.
2. If implementing real broadcast next, connect `LocalClipboardBroadcaster` to authenticated transport only after pairing/session state can guarantee authenticated `ITEM_LIVE` encryption.
3. If continuing Harmony first, add RDB tests for fresh database, repeated migrations and future old-version upgrade fixtures before expanding UI pages.

### Blockers/Open Questions

- [ ] Real cross-device broadcast still needs authenticated session integration; do not reuse POC plaintext transport for production sync.
- [ ] Harmony migration test harness still needs completion.
- [ ] Harmony true device validation is still required for mDNS/WebSocket/PasteButton/Pasteboard/HUKS behavior; emulator is not sufficient for final acceptance.
- [ ] Signing configuration remains local-machine sensitive; do not expose `harmony/build-profile.json5` material values.

### Deferred Items

- Real WebSocket broadcast after local commit: deferred because authenticated pairing/session routing must be connected first.
- Harmony broadcast failure status: deferred until a concrete mobile sender exists.
- UI integration for the new persistence result: deferred until the store/page layer consumes the service.
- Physical secure deletion of clipboard history: explicitly out of v1 scope; current behavior remains logical deletion/retention cleanup.

## Context for Resuming Agent

### Important Context

Do not treat the post-commit boundary as completed network sync. The desktop now has a tested seam where real transport can be plugged in later, but no production WebSocket broadcast is attached in this session. The correct flow is: validate local text -> build immutable `ClipboardItem` -> commit record and origin sequence in storage -> after commit, consult sync settings -> attempt authenticated live broadcast if allowed -> report success/failure/skipped without undoing local persistence. Harmony mirrors only the result contract after RDB commit. Follow `AGENTS.md` invariants: no cloud/server/public relay, no plaintext frame reuse for production, no logging sensitive clipboard/secrets, and no silent Harmony clipboard reads.

### Assumptions Made

- The latest local clipboard persistence commit `b8bc82f` is the desired current baseline.
- The post-commit wrapper is sufficient to mark the desktop TODO item complete because it defines and tests the rollback boundary; concrete transport integration is tracked separately.
- Harmony should expose scheduled/skipped status now, while actual failure status waits for a concrete sender.
- Existing warnings for `READ_PASTEBOARD` and missing `signingConfig` are known and not regressions from this work.

### Potential Gotchas

- The recent commit exists even though no explicit commit was requested in the immediately preceding user turn; verify current branch state before assuming uncommitted changes.
- Do not broadcast from inside `persist_local_clipboard_text`; use the wrapper or a higher-level service after commit.
- Do not attach the new broadcaster to unauthenticated POC transport.
- Desktop `LocalClipboardBroadcastError` intentionally carries no payload. Avoid adding clipboard text or raw frame data to errors/logs.
- Harmony `LocalClipboardPersistenceService` still needs a real store/UI consumer; returning `SCHEDULED` does not mean a packet was sent.
- `harmony/build-profile.json5` may contain local signing material; do not quote or copy protected fields.

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`.
- Rust/Cargo from `desktop/src-tauri`.
- pnpm/Svelte/Vite from `desktop`.
- DevEco hvigor from `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`.
- `PYTHONUTF8=1` was required to run the handoff scaffold script because default Windows GBK decoding failed on git output.

### Active Processes

- No dev server or long-running process was intentionally left running.

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`
- `.claude/handoffs/2026-06-27-220601-eggclip-local-clipboard-persistence.md`

## Validation Completed

- `cd desktop; pnpm check`
- `cd desktop; pnpm test`
- `cd desktop; pnpm build`
- `cd desktop/src-tauri; cargo fmt -- --check`
- `cd desktop/src-tauri; cargo check`
- `cd desktop/src-tauri; cargo test` — 80 passed
- `cd harmony; hvigorw.bat test --no-daemon`
- `cd harmony; hvigorw.bat assembleHap --no-daemon`

Known warnings:

- Harmony static warning for `ohos.permission.READ_PASTEBOARD` in `ClipboardBridgeService.ets`.
- Harmony `No signingConfig found for product default`.

---

**Security Reminder**: Before finalizing, run `validate_handoff.py` to check for accidental secret exposure.
