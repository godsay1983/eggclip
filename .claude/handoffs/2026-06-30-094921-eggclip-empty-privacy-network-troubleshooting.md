# Handoff: EggClip empty states, privacy copy, and network troubleshooting

## Session Metadata

- Created: 2026-06-30 09:49:21
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: about 2 short continuation turns covering UI copy, troubleshooting cards, validation, commits, and handoff capture
- Git state at handoff creation: `main...origin/main`; no functional changes pending, only this handoff document is untracked

### Recent Commits (for context)

- `156470e feat: 为桌面端和鸿蒙端增加网络排障卡`
- `ce5a34b feat: 改进空状态和隐私说明，更新TODO状态`
- `32b5a69 docs: 添加局域网诊断功能的交接文档`
- `666e6f0 feat: 添加局域网诊断功能，展示连接状态和网络信息`
- `912ecd8 feat: 保存历史策略时立即执行retention清理`

## Handoff Chain

- **Continues from**: [2026-06-28-223118-eggclip-lan-diagnostics.md](./2026-06-28-223118-eggclip-lan-diagnostics.md)
  - Previous title: EggClip LAN diagnostics
- **Supersedes**: None; this handoff adds the post-diagnostics empty-state, privacy, and network troubleshooting slice.

## Current State Summary

EggClip is at commit `156470e` with a clean worktree except for this handoff document. Since the previous LAN diagnostics handoff, two small cross-end UI/product slices were completed and committed. First, desktop and HarmonyOS got clearer empty states and privacy copy: desktop recent history distinguishes "no local history" from "history disabled", desktop settings has a privacy boundary card, Harmony home reacts to connection failed/paused states, and Harmony settings now explicitly documents LAN-only, PasteButton-triggered reads, local retention, diagnostics boundaries, and foreground-only sync. Second, both ends got actionable network troubleshooting: desktop settings now has a network troubleshooting card with manual endpoint, firewall, AP isolation, and VPN/TUN checks; Harmony device page now has a connection troubleshooting card that explains mDNS fallback, manual IP, emulator VPN/TUN behavior, and the fact that discovered candidates are not trusted devices.

## Codebase Understanding

## Architecture Overview

The recent work is intentionally UI/store-facing only. Desktop remains layered as Svelte components plus typed store/API boundaries; the new troubleshooting card consumes existing `PocTransportSummary` from `shellSnapshot` and does not access sockets, clipboard, SQLite, or Rust commands directly. Harmony remains ArkUI native: `HomePage.ets`, `DevicesPage.ets`, and `SettingsPage.ets` render state from `PocConnectionStore`, `HistoryStore`, and `SettingsStore`; pages still avoid direct RDB/network service ownership except through established stores. The current POC transport is still unauthenticated and must be treated as diagnostic/manual-only while formal pairing, authenticated WebSocket lifecycle, and crypto integration remain pending.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `AGENTS.md` | Project-wide constraints | Defines LAN-only, text/plain, clipboard, logging, architecture, and validation boundaries |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop implementation plan | Updated with completed empty-state/privacy/troubleshooting subtasks |
| `HARMONY_DEVELOPMENT_TODO.md` | HarmonyOS implementation plan | Updated with completed empty-state/privacy/troubleshooting subtasks |
| `desktop/src/lib/components/clipboard/HistoryList.svelte` | Desktop recent history UI | Now distinguishes no history from disabled history and keeps content metadata-only |
| `desktop/src/lib/components/devices/NetworkTroubleshootingCard.svelte` | Desktop network troubleshooting UI | New safe troubleshooting card using structured transport summary |
| `desktop/src/routes/+page.svelte` | Desktop app shell/settings popover | Integrates privacy summary and network troubleshooting card |
| `desktop/src/app.css` | Desktop visual styling | Adds privacy summary and empty-state styling with dark-theme support |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Harmony home clipboard UI | Adds connection-aware empty copy and richer empty history card |
| `harmony/entry/src/main/ets/pages/DevicesPage.ets` | Harmony device/connectivity UI | Adds connection troubleshooting card |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | Harmony settings/privacy UI | Expands privacy card into explicit safety points |

## Key Patterns Discovered

- Keep the home pages focused on clipboard send/receive and history metadata; network discovery and diagnostic details belong in settings/device surfaces.
- It is acceptable to show actionable network details such as local IPv4, port, mDNS state, candidate counts, firewall/AP isolation guidance, and VPN/TUN hints. It is not acceptable to show clipboard body, HMAC digest values, invitations, keys, signing material, or full frames.
- Current history UI remains metadata-only. Do not add body preview/copy from history until the encrypted content/decryption/key-loading design is implemented.
- TODO parent items should stay unchecked if only a sub-slice is complete. Add checked sub-bullets to show real progress without overstating overall completion.
- Harmony pages can render state from stores and call store methods; do not move mDNS/WebSocket/RDB logic into page files.

## Work Completed

## Tasks Finished

- [x] Desktop recent history empty state now distinguishes "no local history" and "history disabled".
- [x] Desktop history empty state explicitly states body preview waits for encryption/decryption integration and that clearing/disabling history does not modify the system clipboard.
- [x] Desktop settings popover now includes a privacy boundary card covering LAN-only operation, no account/cloud/relay, local history, and safe diagnostics.
- [x] Harmony home clipboard empty state now changes text for failed or paused connection states.
- [x] Harmony home recent-history empty state now distinguishes "no local history" and "history disabled".
- [x] Harmony settings privacy card now explains LAN-only sync, PasteButton-triggered reads, local RDB retention, diagnostics safety, and foreground-only sync.
- [x] Desktop settings now includes `NetworkTroubleshootingCard` with manual endpoint, firewall, AP isolation, and VPN/TUN checks.
- [x] Harmony device page now includes a connection troubleshooting card for mDNS failure, manual IP fallback, VPN/TUN/emulator behavior, and POC trust boundary.
- [x] Both TODO documents were updated with checked sub-bullets reflecting the exact completed slices.

## Files Modified

The latest functional changes are already committed in `ce5a34b` and `156470e`. Current uncommitted change is only this handoff file.

| File | Changes | Rationale |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Added checked sub-bullets for empty-state, reduced-motion, privacy boundary, and troubleshooting progress | Keep desktop plan aligned without overstating incomplete parent items |
| `HARMONY_DEVELOPMENT_TODO.md` | Added checked sub-bullets for home empty states, privacy diagnostics, and device troubleshooting | Keep Harmony plan aligned with implemented visible behavior |
| `desktop/src/app.css` | Added privacy card and empty-state styles, including dark-mode variants | Support new desktop settings/empty-state UI |
| `desktop/src/lib/components/clipboard/HistoryList.svelte` | Added `historyEnabled` prop and two empty-state modes | Make history state understandable without exposing clipboard body |
| `desktop/src/lib/components/devices/NetworkTroubleshootingCard.svelte` | New component for safe LAN troubleshooting guidance | Give users concrete next steps when discovery/connection fails |
| `desktop/src/routes/+page.svelte` | Passes history-enabled state, renders privacy summary and troubleshooting card | Keep settings as the home for non-clipboard diagnostics and policy information |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Adds connection-aware empty copy and empty-history card | Improve first-use and failure states on the clipboard-focused home |
| `harmony/entry/src/main/ets/pages/DevicesPage.ets` | Adds `TroubleshootingCard`, troubleshooting rows, and contextual hints | Make network failure handling visible in the device/connectivity surface |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | Expands privacy explanation into structured points | Make platform privacy constraints clear to users |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Add troubleshooting as visible cards instead of logs or hidden docs | UI cards, README-only docs, or console logs | The user needs app-visible guidance while testing emulator/phone networking; logs would risk leaking details and are less actionable |
| Keep troubleshooting safe and high-level | Show raw frames/diagnostic payloads or only generic failure copy | Port/address/state and next-step copy are useful; raw frames/content violate project security boundaries |
| Preserve POC trust disclaimer | Treat mDNS candidates as connected devices or label them trusted | mDNS only discovers addresses; formal trust requires pairing/authentication |
| Mark sub-bullets rather than top-level TODO items | Mark entire "empty states" or "diagnostics" parent complete | Some broader work remains, such as full no-device/trusted-device list and formal diagnostic page; sub-bullets are precise |
| Avoid backend/protocol changes in this slice | Implement pairing/crypto/session lifecycle immediately | UI troubleshooting/first-use copy was the next bounded, low-risk, cross-end improvement after LAN diagnostics |

## Pending Work

## Immediate Next Steps

1. Re-check `git status --short --branch` before editing; expected state after this handoff is only this handoff document untracked.
2. Continue TODO-driven development. Recommended next small cross-end slice: improve device-list placeholders into a transitional "POC connection vs trusted device" model, without pretending POC peers are paired/trusted.
3. If moving beyond UI, prioritize formal authenticated WebSocket lifecycle integration before enabling real automatic sync semantics over network.
4. If continuing Harmony lifecycle work, verify foreground/background listener/timer behavior and update TODO only with concrete observed behavior.

## Blockers/Open Questions

- [ ] Formal pairing/invitation is not implemented; device list cannot yet show real trusted devices, public-key fingerprints, rename, remove, or key rotation.
- [ ] Formal authenticated WebSocket lifecycle is not connected to the POC connection UI; POC remains unauthenticated and manually driven.
- [ ] History body preview/copy still needs the encrypted-content/decryption/key-loading design.
- [ ] Harmony CryptoFramework/HUKS real cryptographic operations are still pending for Ed25519, X25519, HKDF, and AES-GCM.
- [ ] Desktop system credential storage and production identity-key generation remain pending.

## Deferred Items

- Real device management: deferred until pairing/trusted-device persistence exists.
- History body copy/details: deferred until plaintext/decryption path is designed and implemented safely.
- Formal `ITEM_LIVE` broadcast and automatic desktop write: deferred until authenticated session lifecycle is connected.
- Harmony background sync: out of v1 scope; Harmony stays foreground-only.
- Cloud/account/server relay: explicitly out of v1 scope.

## Context for Resuming Agent

## Important Context

- Latest functional commit is `156470e feat: 为桌面端和鸿蒙端增加网络排障卡`.
- `main` and `origin/main` both point at `156470e` at handoff creation.
- `git status --short --branch` at handoff creation reports `## main...origin/main` plus only this untracked handoff file.
- The previous handoff `2026-06-28-223118-eggclip-lan-diagnostics.md` captured the structured diagnostics foundation. This handoff captures the follow-up user-facing copy and troubleshooting UX.
- Recent validation after the two UI slices passed:
  - `desktop`: `pnpm check`
  - `desktop`: `pnpm test`
  - `desktop`: `pnpm build`
  - `harmony`: `hvigorw.bat test --no-daemon`
  - `harmony`: `hvigorw.bat assembleHap --no-daemon`
- No Rust backend files changed in these two UI slices, so cargo checks were not rerun for them.
- Known Harmony warnings remain expected: Pasteboard permission warning, many RDB "Function may throw exceptions" warnings, and no signingConfig.
- Keep UI diagnostics and troubleshooting free of clipboard body text, invitations, HMAC digests, keys, certificate material, protected signing fields, and full network frames.
- Harmony clipboard reads must continue to use the real system `PasteButton`; do not replace it with a normal button or attempt silent reads.

## Assumptions Made

- The user wants incremental progress by the desktop/Harmony TODO plans, not a broad rewrite.
- Current POC networking remains useful for manual testing and troubleshooting, but it is not an authentication boundary.
- Showing ordinary local IPv4 and port for manual troubleshooting is acceptable; showing secrets/content is not.
- The committed UI slices are complete enough for handoff because automated desktop/Harmony checks passed.

## Potential Gotchas

- The handoff scaffold script should be run with `PYTHONUTF8=1` on this Windows machine to avoid GBK decode issues.
- `NetworkTroubleshootingCard.svelte` is a frontend-only helper. Do not move socket or OS network logic into it.
- Harmony `DevicesPage.ets` now has POC connection controls and troubleshooting text; do not label POC peers as trusted devices.
- TODO parent checkboxes may remain unchecked even when new checked sub-bullets exist. This is intentional.
- `harmony/build-profile.json5` may contain local signing configuration. Do not expose or commit protected signing material or machine-local secrets.
- The project may have `.gitattributes`/line-ending behavior that prints LF-to-CRLF warnings; these were observed previously and are not functional failures.

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

For commits `ce5a34b` and `156470e`:

- Desktop frontend: `pnpm check` passed.
- Desktop frontend tests/build: `pnpm test` and `pnpm build` passed.
- HarmonyOS: `hvigorw.bat test --no-daemon` passed with known warnings.
- HarmonyOS: `hvigorw.bat assembleHap --no-daemon` passed with known warnings.

For this handoff:

- `git status --short --branch` checked: only this handoff file should be pending.
- Handoff validation should be run after saving this document.

## Related Resources

- [Previous handoff: LAN diagnostics](./2026-06-28-223118-eggclip-lan-diagnostics.md)
- [Earlier handoff: local history capture](./2026-06-28-193205-eggclip-local-history-capture.md)
- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`

---

Security check note: this handoff intentionally excludes clipboard body samples, invitations, HMAC digests, keys, certificate material, signing `material` fields, protected passwords, and full network frames.
