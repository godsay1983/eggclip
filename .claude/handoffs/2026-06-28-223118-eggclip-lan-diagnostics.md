# Handoff: EggClip LAN diagnostics

## Session Metadata

- Created: 2026-06-28 22:31:18
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: about 20 minutes for handoff capture and validation
- Git state at handoff creation: `main...origin/main`; no code changes pending, only this handoff document is untracked

### Recent Commits (for context)

- `666e6f0 feat: 添加局域网诊断功能，展示连接状态和网络信息`
- `912ecd8 feat: 保存历史策略时立即执行retention清理`
- `fa8b80f feat: 桌面端与鸿蒙端实现自动接收暂停策略`
- `27e3d35 feat: 同步关闭时暂停POC发送并显示状态`
- `bb6f837 refactor: 重构设置页开关行，移除通用组件改用内联实现`

## Handoff Chain

- **Continues from**: [2026-06-28-193205-eggclip-local-history-capture.md](./2026-06-28-193205-eggclip-local-history-capture.md)
  - Previous title: EggClip local history capture
- **Supersedes**: None; this handoff adds the post-local-history LAN diagnostics milestone.

## Current State Summary

EggClip is currently at a clean `main` state with the latest functional commit `666e6f0`, which adds user-visible LAN diagnostics to both desktop and HarmonyOS settings surfaces. Desktop settings now show a diagnostic card for WebSocket state, listen port, mDNS publication state, candidate IPv4 addresses, peer count, and recent transport error. HarmonyOS settings now show mDNS state, discovery candidate count, WebSocket state, and frame statistics from the shared POC connection store. Diagnostics intentionally stay safe: they do not display clipboard body text, invitations, digests, keys, certificate material, or full frames. The only pending file is this handoff document.

## Codebase Understanding

## Architecture Overview

Desktop diagnostics follow the existing Tauri/Svelte boundary: Rust exposes transport status through commands, `desktop/src/lib/api/` maps command DTOs into frontend types, `desktop/src/lib/stores/` owns state orchestration, and Svelte components only render typed state. Harmony diagnostics follow the existing ArkUI layering: `SettingsPage.ets` subscribes to `PocConnectionStore`, renders derived diagnostic state, and does not directly access mDNS, WebSocket internals, RDB, clipboard body data, or protocol secrets.

The current app is still in the POC-to-formal-protocol transition. POC WebSocket/mDNS remains useful for local development and user-visible diagnostics, but authenticated pairing, formal `ITEM_LIVE` lifecycle, real CryptoFramework/HUKS on Harmony, and full sync lifecycle are still pending TODO items.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `AGENTS.md` | Project-wide development constraints | Defines LAN-only, text/plain, clipboard, architecture, logging, and validation boundaries |
| `docs/EggClip最佳实现方案.md` | Product and architecture decision source | Must be updated before expanding product/security scope |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop implementation plan | Latest diagnostics subtask is marked complete; next desktop slices should remain TODO-driven |
| `HARMONY_DEVELOPMENT_TODO.md` | HarmonyOS implementation plan | Latest diagnostics subtask is marked complete; privacy/empty states/lifecycle remain open |
| `desktop/src/lib/types/shell.ts` | Frontend shell DTO types | Defines `PocTransportSummary` and candidate address summary used by diagnostics |
| `desktop/src/lib/api/shell.ts` | Typed Tauri command wrapper | Converts transport status DTO into a safe frontend summary and display string |
| `desktop/src/lib/stores/shell.ts` | Desktop UI orchestration store | Stores `pocTransport` and refreshes diagnostic state |
| `desktop/src/lib/components/devices/NetworkDiagnosticsCard.svelte` | Desktop diagnostics UI | Renders safe LAN diagnostics in the settings popover |
| `desktop/src/routes/+page.svelte` | Desktop app shell page | Integrates the diagnostics card into the settings popover |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | Harmony settings page | Subscribes to `PocConnectionStore` and renders the diagnostics card |

## Key Patterns Discovered

- Keep diagnostics derived from existing store/service state. Do not let UI components directly open sockets, inspect RDB, or read clipboard content.
- Diagnostics may show state, counts, ports, short labels, and error category text. They must not show clipboard content, invitation values, HMAC digests, long-term keys, signing material, or complete network frames.
- Desktop Svelte components should depend on typed API/store objects, not raw Tauri `invoke` results.
- Harmony pages may subscribe to stores and render derived state, but service-level network behavior remains in `services/` and `store/`.
- The POC path is unauthenticated. Do not expand it into automatic sensitive behavior or treat it as the final security model.

## Work Completed

## Tasks Finished

- [x] Added desktop LAN diagnostics card in the settings popover.
- [x] Added desktop frontend transport summary typing for WebSocket state, mDNS state, candidate IPv4 addresses, peer count, port, and latest error.
- [x] Updated desktop shell store to keep structured `pocTransport` state and refresh it on demand.
- [x] Added HarmonyOS settings diagnostics card backed by `PocConnectionStore`.
- [x] Updated HarmonyOS diagnostics to show mDNS status, candidate count, WebSocket status, and frame statistics.
- [x] Updated desktop and Harmony TODO documents with completed diagnostics subtasks.
- [x] Confirmed current repo state is clean except for this handoff document.

## Files Modified

The latest functional changes are already committed in `666e6f0`. Current uncommitted change is only this handoff file.

| File | Changes | Rationale |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Added completed diagnostics subtask under settings/device diagnostics | Keep plan aligned with implemented desktop diagnostics |
| `HARMONY_DEVELOPMENT_TODO.md` | Added completed diagnostics subtasks under settings/privacy | Keep plan aligned with implemented Harmony diagnostics and safe diagnostic boundary |
| `desktop/src/lib/types/shell.ts` | Added structured POC transport summary types | Avoid opaque string-only status and support richer diagnostics UI |
| `desktop/src/lib/api/shell.ts` | Mapped Tauri POC transport status into frontend-safe summary and status description | Preserve API boundary and sanitize what UI renders |
| `desktop/src/lib/stores/shell.ts` | Stored and refreshed `pocTransport` state | Keep diagnostics state centralized in the shell store |
| `desktop/src/lib/components/devices/NetworkDiagnosticsCard.svelte` | New desktop diagnostics component | Show LAN diagnostics without exposing sensitive data |
| `desktop/src/routes/+page.svelte` | Integrated diagnostics card into settings popover | Put network diagnostics in settings, not the clipboard-focused home surface |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | Added diagnostics state subscription and card rendering | Surface mobile LAN diagnostics through existing settings page |
| `.claude/handoffs/2026-06-28-223118-eggclip-lan-diagnostics.md` | New handoff document | Preserve context for the next session |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Put diagnostics in settings surfaces | Show on home page, create separate diagnostics page, or put in settings | Home should stay focused on clipboard operations; settings is the right place for troubleshooting details |
| Use structured desktop transport state instead of a formatted string only | Keep previous display string or expose structured fields | Structured fields make UI clearer and prevent fragile parsing in Svelte components |
| Show candidate IPv4 addresses but not secrets/content | Hide all network detail or show full frames | Users need actionable LAN troubleshooting data; full frames/content would violate project security rules |
| Subscribe Harmony settings to `PocConnectionStore` | Read services directly from the page or duplicate state | Store subscription preserves layering and avoids page-level network ownership |
| Leave formal authenticated lifecycle for later | Fold diagnostics work into formal session lifecycle | Diagnostics is a bounded UI/observability slice; authenticated lifecycle remains a larger planned protocol task |

## Pending Work

## Immediate Next Steps

1. Re-check `git status --short --branch` before editing; only this handoff should be pending unless the user has changed files.
2. Continue TODO-driven development with a small cross-end slice. Recommended next slice: complete user-facing privacy/empty-state copy on both ends, because diagnostics are now visible but first-use/no-history/network-failure states remain incomplete.
3. If choosing a protocol/security slice instead, prioritize formal session lifecycle integration: connect authenticated transport frame processors to real WebSocket peer lifecycle before replacing POC sync behavior.
4. If choosing Harmony crypto work, replace transitional digest/vector shape checks with real CryptoFramework/HUKS operations against shared vectors.

## Blockers/Open Questions

- [ ] Formal pairing and authenticated session lifecycle are not complete; current mDNS/WebSocket diagnostics are still POC-oriented.
- [ ] Harmony CryptoFramework/HUKS real Ed25519/X25519/HKDF/AES-GCM execution is still pending; some ArkTS tests currently validate vector shape and canonical construction rather than platform crypto execution.
- [ ] History body preview/copy still needs a safe plaintext/decryption design before exposing stored content.
- [ ] Real trusted device list, device rename/removal, and key rotation require pairing/identity work first.

## Deferred Items

- Formal `ITEM_LIVE` broadcast over authenticated sessions: deferred until real WebSocket authenticated lifecycle is connected.
- Automatic desktop clipboard write for authenticated remote live items: deferred until formal `ITEM_LIVE` receive path is connected; do not add this to unauthenticated POC.
- Harmony background sync: out of v1 boundary; HarmonyOS side should remain foreground-only.
- Cloud/account/server relay: explicitly out of scope for v1.

## Context for Resuming Agent

## Important Context

- Latest functional commit is `666e6f0 feat: 添加局域网诊断功能，展示连接状态和网络信息`.
- At handoff creation, `git status --short --branch` reports `## main...origin/main` plus only this untracked handoff document.
- Previous local-history handoff is `2026-06-28-193205-eggclip-local-history-capture.md`; read it if continuing history or retention work.
- Desktop diagnostics were validated at the frontend level with `pnpm check`, `pnpm test`, and `pnpm build`. No desktop Rust code changed in the diagnostics slice, so cargo checks were not rerun for that slice.
- Harmony diagnostics were validated with `hvigorw.bat test --no-daemon` and `hvigorw.bat assembleHap --no-daemon`. Known warnings are expected: pasteboard permission warning, many "Function may throw exceptions" warnings, and no signingConfig.
- Do not display or log clipboard body text, invitations, keys, HMAC digests, signing material, or full network frames in diagnostics, docs, tests, or error messages.
- POC transport is unauthenticated. It can be used for development visibility and manual user-triggered copy/send flows, but not as a final security boundary.
- Harmony must keep using the real ArkUI `PasteButton` for clipboard reads. Do not replace it with a normal button or try to silently read clipboard content.

## Assumptions Made

- The user wants development to continue by the existing desktop/Harmony TODO plans.
- The latest committed diagnostics work is acceptable as the milestone to capture in this handoff.
- No background dev servers or watchers need to be preserved across sessions.
- The handoff document itself does not need to be committed unless the user explicitly asks for commit/stage work.

## Potential Gotchas

- The handoff scaffold script can fail on Windows if Python tries to decode git output as GBK. Run it with `PYTHONUTF8=1`.
- Do not mark parent TODO checkboxes complete just because a sub-bullet is done. Several top-level items remain unchecked because formal implementation is incomplete.
- Desktop settings now include diagnostics; do not re-add network/debug cards to the home page, because home was intentionally reduced to clipboard-related functionality.
- Harmony settings already owns diagnostics and privacy/settings concerns; home should remain clipboard-focused.
- If adding more diagnostics, keep them bounded to status/counts/safe identifiers. Avoid raw payloads, message bodies, digest values, invitations, or key references.
- If touching `harmony/build-profile.json5`, do not expose or commit signing `material`, certificate paths, protected fields, or local machine secrets.

## Environment State

### Tools/Services Used

- PowerShell on Windows.
- Git in `D:\Develop\eggclip`.
- Python handoff scripts from `C:\Users\caozhipeng\.agents\skills\session-handoff`.
- Desktop validation tools: pnpm, Svelte check, Vitest, Vite.
- Harmony validation tools: DevEco Studio JBR and hvigor.

### Active Processes

- No dev servers, app processes, watchers, or background validation processes were intentionally left running.

### Environment Variables

- `PYTHONUTF8` for handoff tooling on Windows.
- `JAVA_HOME`, `DEVECO_SDK_HOME`, and `Path` for Harmony validation.

## Verification Completed

For the latest diagnostics functional commit:

- Desktop frontend: `pnpm check` passed.
- Desktop frontend tests/build: `pnpm test` and `pnpm build` passed.
- HarmonyOS: `hvigorw.bat test --no-daemon` passed with known warnings.
- HarmonyOS: `hvigorw.bat assembleHap --no-daemon` passed with known warnings.

For this handoff:

- `git status --short --branch` checked: only this handoff file is pending.
- Handoff validation should be run after saving this document.

## Related Resources

- [Previous handoff: local history capture](./2026-06-28-193205-eggclip-local-history-capture.md)
- [Earlier handoff: history metadata preview](./2026-06-28-174850-eggclip-history-metadata-preview.md)
- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`

---

Security check note: this handoff intentionally excludes clipboard body samples, invitations, HMAC digests, keys, certificate material, signing `material` fields, protected passwords, and full network frames.
