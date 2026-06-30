# Handoff: EggClip recent POC endpoint persistence and Harmony history clear

## Session Metadata

- Created: 2026-06-30 11:56:08
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: approximately 1 hour

### Recent Commits (for context)

- `099dd38` feat: 记录最近成功POC端点，支持回填和快速连接
- `cf1c09a` feat: 添加剪贴板发送状态指示，区分本机记录、等待连接、发送中、已发送、失败和同步暂停
- `32aa213` feat: 添加POC设备卡片及元数据展示
- `c031a0b` docs: 新增EggClip空状态、隐私说明和网络排障功能的交接文档
- `156470e` feat: 为桌面端和鸿蒙端增加网络排障卡

## Handoff Chain

- **Continues from**: [2026-06-30-094921-eggclip-empty-privacy-network-troubleshooting.md](./2026-06-30-094921-eggclip-empty-privacy-network-troubleshooting.md)
  - Previous title: EggClip empty states, privacy copy, and network troubleshooting
- **Supersedes**: None

## Current State Summary

This session continued the planned desktop and HarmonyOS feature work. The main completed work is persistence of the most recent successful POC endpoint on both platforms, plus a HarmonyOS homepage “clear local history” action to match desktop behavior. All changes are currently uncommitted in the working tree. Validation passed for desktop frontend, Rust backend, and HarmonyOS test/build. The project remains in a POC-to-product transition: recent endpoints are explicitly diagnostic POC addresses, not trusted devices or authentication state.

## Codebase Understanding

## Architecture Overview

EggClip has three active layers:

- Desktop frontend: Svelte components call typed APIs in `desktop/src/lib/api/`, then stores in `desktop/src/lib/stores/` orchestrate UI state.
- Desktop backend: Tauri commands in Rust expose transport, history, settings, clipboard, and storage services. Commands validate inputs and delegate to module logic.
- HarmonyOS: ArkUI pages compose stores and services. `pages/` should stay UI-focused, `store/` orchestrates state, `data/repositories/` handles RDB persistence, and transport/clipboard logic stays in `services/`.

The POC WebSocket path is still intentionally separate from the formal authenticated protocol path. It is only for manual LAN verification and must not be treated as trusted sync.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/src-tauri/src/transport/mod.rs` | Desktop POC WebSocket transport and Tauri commands | Now persists and loads recent active outbound POC endpoint metadata |
| `desktop/src-tauri/src/lib.rs` | Tauri command registration | Registers `load_poc_recent_endpoint` |
| `desktop/src/lib/api/shell.ts` | Typed frontend wrapper around Tauri shell commands/events | Maps recent endpoint DTOs to UI objects |
| `desktop/src/lib/stores/shell.ts` | Desktop shell state orchestration | Loads recent endpoint at startup and remembers successful active outbound connections |
| `desktop/src/lib/components/devices/PocConnectCard.svelte` | Desktop manual POC connection UI | Already exposes “recent successful address” and “回填并连接” |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | Harmony RDB repositories | Stores and validates recent POC endpoint metadata in `app_metadata` |
| `harmony/entry/src/main/ets/store/PocConnectionStore.ets` | Harmony POC discovery/connection state | Loads persisted endpoint, fills manual host/port, saves successful connections |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Harmony history summary/actions | Added `clearAll()` for local history logical deletion |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Harmony homepage clipboard/history UI | Added “清空” button for recent history |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop plan/status | Updated D4 recent successful address status |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony plan/status | Updated recent endpoint and homepage history clear status |

## Key Patterns Discovered

- Do not save inbound peer socket addresses as “recent endpoint” on desktop. Inbound WebSocket peer ports are usually ephemeral and not useful for reconnecting.
- POC endpoint persistence must remain low-trust metadata. Save only host, port, and timestamp. Do not save device identity, keys, invitations, clipboard body, digest, or trusted-device assertions.
- Harmony history actions should refresh `HistoryStoreSnapshot` and update `historyUsed`, `historyLimit`, and `historyItems` together.
- Both platforms already have settings/RDB infrastructure; reuse `SettingsRepository` / `SettingsRdbRepository` rather than adding new storage paths.
- TODO files should mark completed subitems immediately, otherwise the plan starts accumulating stale “待接入” descriptions.

## Work Completed

## Tasks Finished

- [x] Desktop: persist recent successful active outbound POC endpoint after successful manual WebSocket connect.
- [x] Desktop: expose `load_poc_recent_endpoint` Tauri command and load it on Svelte page mount.
- [x] Desktop: keep inbound POC peer events out of recent endpoint persistence to avoid storing ephemeral remote ports.
- [x] HarmonyOS: persist recent successful POC endpoint in `app_metadata` with strict IPv4/port/timestamp validation.
- [x] HarmonyOS: load persisted recent endpoint during `PocConnectionStore.initialize()` and fill manual connection fields when empty.
- [x] HarmonyOS: add homepage “清空” action for local history, with operation guard against simultaneous delete/clear.
- [x] TODO: update desktop and Harmony plans to reflect recent endpoint persistence and Harmony homepage history clear.
- [x] Validation: desktop check/test/build, Rust fmt/check/test, Harmony test/assembleHap all passed.

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src-tauri/src/transport/mod.rs` | Added `PocRecentEndpoint`, persistence helpers, load command, changed `connect_poc_peer` to return endpoint metadata, added regression test | Desktop needs restart-safe recent address fallback without treating it as trusted identity |
| `desktop/src-tauri/src/lib.rs` | Registered `transport::load_poc_recent_endpoint` | Makes backend load command available to frontend |
| `desktop/src/lib/types/shell.ts` | Added `connectedAtMs` to `PocRecentEndpoint` | Preserve machine timestamp while still showing localized time label |
| `desktop/src/lib/api/shell.ts` | Added endpoint DTO mapping, `loadPocRecentEndpoint()`, changed `connectPocPeer()` return type | Keep frontend API typed and consistent with Rust command |
| `desktop/src/lib/stores/shell.ts` | Added startup load of recent endpoint, endpoint remembering, and outbound-only persistence behavior | Centralizes desktop UI state and avoids storing inbound ephemeral addresses |
| `desktop/src/routes/+page.svelte` | Calls `shellSnapshot.loadRecentPocEndpoint()` on mount | Restores recent address after app restart |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | Added `RecentPocEndpointRecord`, save/load methods, IPv4 validation helpers | Harmony needs restart-safe POC address fallback stored in app metadata |
| `harmony/entry/src/main/ets/store/PocConnectionStore.ets` | Loads/saves recent endpoint, fills manual fields, keeps last successful label/time | Enables device page “连接上次地址” across app restarts |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Added `clearAll()` | Gives homepage a store-level history clear action |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Added clearing state, “清空” button, and clear action handler | Matches desktop history behavior while preserving Harmony clipboard rules |
| `DESKTOP_DEVELOPMENT_TODO.md` | Marked POC recent active outbound address persistence complete | Keeps plan accurate |
| `HARMONY_DEVELOPMENT_TODO.md` | Marked recent endpoint persistence and homepage history clear complete; cleaned stale wording | Keeps plan accurate |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Persist only active outbound POC endpoints | Save all connected peer addresses; save only manual outbound targets; save nothing | Inbound peer ports are ephemeral. Manual/outbound target is the only useful reconnect address. |
| Store POC endpoint in existing app metadata/settings repository | Add new table; use settings repository metadata; keep memory-only | Existing metadata storage is sufficient and avoids schema churn for diagnostic POC data. |
| Treat recent endpoint as non-trusted metadata | Promote it into device list; label it as trusted; label as POC-only | mDNS/manual IP is discovery/connectivity only. Trust still requires pairing and authentication. |
| Add Harmony homepage clear history before history copy/details | Implement copy/details first; add clear only; defer all history actions | Desktop already had clear/delete. Harmony had delete but not clear, so clear was a small, user-visible parity improvement. Copy/details require content decryption design. |

## Pending Work

## Immediate Next Steps

1. Continue TODO-driven feature work, preferably in the formal protocol/security path: connect authenticated session frame processor to real WebSocket lifecycle, or start production identity key persistence.
2. Add protocol/auth integration without weakening POC boundaries: POC recent address should remain a connection hint, not a trusted device.
3. For user-visible history, decide when ciphertext decryption is available; only then implement history正文 preview/copy/detail.

## Blockers/Open Questions

- [ ] Formal trusted-device pairing is still not implemented. Device list still uses POC/placeholder semantics.
- [ ] Production key storage is not complete: desktop system credential store and Harmony HUKS integration remain planned work.
- [ ] Harmony history正文 preview/copy/detail depends on the encrypted content/decryption path; do not fake it by storing plaintext.
- [ ] Harmony warnings for `READ_PASTEBOARD` and “Function may throw exceptions” are known but still noisy.

## Deferred Items

- History正文 preview/copy/detail: deferred until real encryption/decryption and plaintext handling rules are in place.
- Reset local identity: deferred until identity key/HUKS/system credential storage flows are explicit.
- Trusted-device rename/remove and space key rotation: deferred until pairing and device identity are complete.
- Real auto-reconnect and PING/PONG: deferred to D4/H5 connection manager work.

## Context for Resuming Agent

## Important Context

- Current working tree has uncommitted changes in 12 tracked files. Do not discard them.
- The latest feature set is already validated locally. If you modify any affected code, rerun the relevant desktop/Harmony validation.
- Recent endpoint persistence intentionally stores only host, port, and timestamp. This is not a security/trust feature.
- Desktop recent endpoint is saved after successful `connect_poc_peer`, not from inbound `onPocPeerConnected`.
- Harmony recent endpoint is saved in `SettingsRdbRepository` under `pocRecentEndpoint`.
- Harmony homepage clear history only marks local RDB history deleted and refreshes the visible metadata list. It does not touch system pasteboard.
- The current POC transport can carry plaintext `clipboardText` JSON only for manual development verification. Formal authenticated protocol code exists separately and must stay separated.
- Never log or document clipboard body, invitation secrets, keys, HMAC digests, signing material, or full frames.

## Assumptions Made

- It is acceptable to persist POC endpoint metadata because it contains no secret material and is already shown to the user in diagnostics/manual connection UI.
- The desktop “recent successful address” should be based on active manual/outbound connection attempts.
- The Harmony homepage can expose clear history because SettingsPage already had a similar clear history capability and the operation does not alter system clipboard.
- Current warnings in Harmony builds are expected unless they become actual errors.

## Potential Gotchas

- The scaffold script can fail on Windows if Python subprocess decodes git output with GBK. Use `PYTHONUTF8=1` when running session-handoff scripts in this repository.
- `git diff --check` emits CRLF conversion warnings because Git will normalize line endings. It did not report whitespace errors.
- Do not convert POC endpoint metadata into trusted device state. That would violate the security model.
- Do not implement Harmony clipboard silent reads. Reads must still go through real `PasteButton`.
- Do not display history正文 until a secure decryption path exists.
- If editing `harmony/build-profile.json5`, do not expose or commit signing `material`, passwords, certificate paths, or local signing files.

## Environment State

## Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Python handoff scripts from `C:\Users\caozhipeng\.agents\skills\session-handoff\scripts`
- Desktop validation:
  - `pnpm check`
  - `pnpm test`
  - `pnpm build`
  - `cargo fmt -- --check`
  - `cargo check`
  - `cargo test`
- Harmony validation:
  - `hvigorw.bat test --no-daemon`
  - `hvigorw.bat assembleHap --no-daemon`

## Active Processes

- No dev server or watcher intentionally left running.

## Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8` was used for the handoff scaffold retry.

## Validation Results

- Desktop `pnpm check`: passed, 0 Svelte errors/warnings.
- Desktop `pnpm test`: passed, 1 test file / 3 tests.
- Desktop `pnpm build`: passed.
- Desktop Rust `cargo fmt -- --check`: passed.
- Desktop Rust `cargo check`: passed.
- Desktop Rust `cargo test`: passed, 87 tests.
- Harmony `hvigorw.bat test --no-daemon`: passed.
- Harmony `hvigorw.bat assembleHap --no-daemon`: passed.
- `git diff --check`: no whitespace errors; only line-ending conversion warnings were printed by Git.

## Current Working Tree

Modified files at handoff time:

- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `desktop/src-tauri/src/lib.rs`
- `desktop/src-tauri/src/transport/mod.rs`
- `desktop/src/lib/api/shell.ts`
- `desktop/src/lib/stores/shell.ts`
- `desktop/src/lib/types/shell.ts`
- `desktop/src/routes/+page.svelte`
- `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets`
- `harmony/entry/src/main/ets/pages/HomePage.ets`
- `harmony/entry/src/main/ets/store/HistoryStore.ets`
- `harmony/entry/src/main/ets/store/PocConnectionStore.ets`

Diff size at handoff time: 12 files changed, approximately 320 insertions and 31 deletions.

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`
- Previous handoff: `.claude/handoffs/2026-06-30-094921-eggclip-empty-privacy-network-troubleshooting.md`

---

**Security Reminder**: This handoff intentionally omits clipboard body, keys, invitations, digests, signing material, and full protocol frames.
