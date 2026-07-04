# Handoff: EggClip pairing invitation generation, safe copy, and Harmony import parsing

## Session Metadata
- Created: 2026-07-04 16:33:15
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: about 2 focused development sessions

### Recent Commits (for context)
  - 457e734 feat: 实现配对邀请解析与UI展示
  - 51acfb3 feat: 添加安全复制配对邀请功能
  - 875ba77 feat: 添加配对邀请生成功能
  - bb143c8 feat: 添加同步空间列表功能并更新UI
  - 37d64eb feat: 抽象凭据存储接口并实现本地同步空间创建命令

## Handoff Chain

- **Continues from**: [2026-06-30-115608-eggclip-recent-endpoint-history-clear.md](./2026-06-30-115608-eggclip-recent-endpoint-history-clear.md)
  - Previous title: EggClip recent POC endpoint persistence and Harmony history clear
- **Supersedes**: None

Review the previous handoff for historical context, but the latest pairing-related state is captured here.

## Current State Summary

The project has moved from local sync-space groundwork into the formal pairing flow. Desktop can create local sync spaces, generate versioned `eggclip://pair` invitations with a high-entropy pairing secret, show a confirmation code, and copy the invitation through a suppressed clipboard path so the invitation does not get recorded by local history. Harmony can now import an `eggclip://pair` invitation string in the Devices page, validate its structure and expiry, compute the same six-digit confirmation code as desktop, and show a parse-only summary. No trusted device is created yet, no space key is transferred yet, and the formal encrypted pairing handshake is still pending.

## Codebase Understanding

## Architecture Overview

EggClip keeps a strict separation between POC transport and formal pairing/sync. Desktop pairing work lives in Rust under `desktop/src-tauri/src/pairing/mod.rs` and is exposed to Svelte through typed Tauri commands in `desktop/src/lib/api/shell.ts` and `desktop/src/lib/stores/shell.ts`. Harmony mirrors this with a service/store/page split: parsing and validation are in `harmony/entry/src/main/ets/services/pairing/PairingInvitationService.ets`, state orchestration is in `harmony/entry/src/main/ets/store/PairingStore.ets`, and UI composition is in `harmony/entry/src/main/ets/pages/PairingPage.ets`, currently embedded in `harmony/entry/src/main/ets/pages/DevicesPage.ets`. Both sides avoid persisting invitation secrets or clipboard body text as plaintext.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `AGENTS.md` | Repository-wide product, security, architecture, and validation rules | Must be read before continuing; defines LAN-only, clipboard, secret, and platform boundaries |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop development plan | Pairing invitation and safe copy progress is recorded here |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony development plan | Harmony invitation import progress is recorded here |
| `desktop/src-tauri/src/pairing/mod.rs` | Desktop sync-space and invitation backend | Generates `eggclip://pair` invitation URI, validates invitation before copy, tests pairing boundaries |
| `desktop/src-tauri/src/clipboard/mod.rs` | Desktop clipboard read/write and suppression | Provides suppressed clipboard write path used by invitation safe copy |
| `desktop/src/routes/+page.svelte` | Desktop settings popover UI | Sync-space card, generate-invite action, and safe-copy UI live here |
| `harmony/entry/src/main/ets/services/pairing/PairingInvitationService.ets` | Harmony invitation parser | Validates `eggclip://pair` URI and computes confirmation code |
| `harmony/entry/src/main/ets/store/PairingStore.ets` | Harmony pairing UI state store | Keeps import parse-only and avoids persistence |
| `harmony/entry/src/main/ets/pages/PairingPage.ets` | Harmony pairing UI card | Invitation input, validation, summary, and safety messaging |
| `harmony/entry/src/test/LocalUnit.test.ets` | Harmony local unit tests | Contains invitation parsing tests and desktop-compatible confirmation-code vector |

### Key Patterns Discovered

- Desktop frontend should only call typed API wrappers in `desktop/src/lib/api/`; Svelte components should not call Tauri commands directly.
- Desktop store methods in `desktop/src/lib/stores/shell.ts` own UI state transitions and user-facing status messages.
- Desktop Rust commands should stay thin and delegate to testable functions that accept a database connection or path.
- Harmony pages should compose UI and call stores; parsing/protocol details belong in services.
- Harmony ArkTS does not allow object spread for plain objects in this project configuration. Use explicit object construction.
- Invitation strings contain a pairing secret. Do not display the full string in UI text, logs, test output, handoff docs, or ordinary status messages.
- Confirmation code must match desktop: SHA-256 over the raw decoded invitation payload JSON bytes, take the first 4 bytes as big-endian u32, then `% 1000000`.

## Work Completed

### Tasks Finished

- [x] Desktop sync-space card can list spaces and create a default space without showing raw keys.
- [x] Desktop can generate a 5-minute `eggclip://pair` invitation from a sync space.
- [x] Desktop invitation includes app/version/kind, space ID, key version, issuer device ID, issuer public key, pairing secret, and expiry.
- [x] Desktop shows confirmation code and issuer short fingerprint without expanding the full invitation string.
- [x] Desktop can safely copy invitation through a backend command that validates the URI and writes it using clipboard suppression.
- [x] Harmony has `PairingInvitationService` for `eggclip://pair` parsing and validation.
- [x] Harmony has `PairingStore` for parse-only invitation import state.
- [x] Harmony `PairingPage` is now a real card embedded at the top of Devices page.
- [x] Harmony tests cover valid invitation, invalid scheme, invalid payload, expired invitation, bad pairing secret length, and store behavior.

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Marked invitation generation and safe-copy subtasks complete; left QR/one-time-consume pending | Keep TODO aligned with actual implementation |
| `HARMONY_DEVELOPMENT_TODO.md` | Marked invitation URI parsing and input import subtasks complete; left scan/PasteButton import/real pairing pending | Keep TODO aligned with actual implementation |
| `desktop/src-tauri/src/pairing/mod.rs` | Added invitation generation, URI validation, safe-copy command, and tests | Establish desktop side of formal pairing invite flow |
| `desktop/src-tauri/src/clipboard/mod.rs` | Added suppressed clipboard write helper reused by invitation copy | Prevent invitation secret from entering local history via clipboard monitor |
| `desktop/src-tauri/src/lib.rs` | Registered new pairing commands | Expose backend functionality to frontend |
| `desktop/src/lib/api/shell.ts` | Added typed invitation generation and copy API wrappers | Maintain typed frontend command boundary |
| `desktop/src/lib/stores/shell.ts` | Added invitation generation/copy state transitions | Keep UI orchestration in store |
| `desktop/src/lib/types/shell.ts` | Added invitation state types | Keep Svelte state typed |
| `desktop/src/routes/+page.svelte` | Added generate invitation and safe-copy UI in sync-space card | Make pairing invite flow visible on desktop |
| `desktop/src/app.css` | Styled sync-space invitation UI | Keep UI polish consistent |
| `harmony/entry/src/main/ets/services/pairing/PairingInvitationService.ets` | Added parser, validation, UTF-8 decode, and pure ArkTS SHA-256 for confirmation code | Support desktop invite import without persisting secrets |
| `harmony/entry/src/main/ets/store/PairingStore.ets` | Added parse-only pairing store | Keep page logic simple and non-persistent |
| `harmony/entry/src/main/ets/pages/PairingPage.ets` | Replaced placeholder with import/validate card | Make invitation import usable on Harmony |
| `harmony/entry/src/main/ets/pages/DevicesPage.ets` | Embedded `PairingPage` above connection cards | Add pairing entry without changing 3-tab navigation |
| `harmony/entry/src/test/LocalUnit.test.ets` | Added invitation parsing and store tests | Lock protocol compatibility and failure cases |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Keep Harmony bottom nav as Home / Devices / Settings and embed pairing in Devices | Add a fourth tab, replace Devices, or add nested navigation | User wanted main UI polished; adding a fourth tab would crowd the HDS floating nav. Pairing logically belongs with device management. |
| Do not show full invitation URI in desktop UI | Show full URI in text area, copy only, or QR only | URI contains pairing secret. Copy-only with explicit safety text reduces accidental exposure. |
| Copy invitation through backend suppressed clipboard path | Frontend clipboard write, ordinary write command, or backend command with validation/suppression | Suppression prevents local clipboard monitor from saving invitation secret to history. Backend validation prevents arbitrary text from using this secret-safe pathway. |
| Harmony import is parse-only | Immediately create device, persist invitation, or start handshake | Safe incremental step. Trusted device creation and spaceKey transfer require real handshake and confirmation flow. |
| Implement small pure ArkTS SHA-256 for confirmation code | Use platform CryptoFramework, use non-matching simple hash, or skip confirmation code | Need deterministic sync with desktop tests. SDK digest API was not quickly available in local type search; pure implementation is testable and isolated. |

## Pending Work

## Immediate Next Steps

1. Add Harmony safe import from clipboard text using real PasteButton or another allowed user-triggered path; do not request general silent pasteboard access.
2. Add desktop QR rendering for the current invitation so Harmony can later scan instead of manual paste.
3. Add “continue pairing” action after Harmony invitation validation: display confirmation code check, then start the formal pairing state machine without persisting secrets prematurely.

### Blockers/Open Questions

- [ ] Decide exact Harmony invite import UX: PasteButton only, manual input only, system scanner, or a combination.
- [ ] Decide how desktop should track one-time invitation consumption and expiry cleanup. Current desktop invitation is generated but not persisted as consumed/expired state.
- [ ] Confirm whether desktop and Harmony confirmation code should remain based on raw invitation payload bytes after future payload field changes; if yes, tests must be updated with stable vectors.
- [ ] Decide QR library or native ArkUI rendering approach for desktop/Harmony scan flow.

### Deferred Items

- QR code rendering and scanning: deferred until string import path was validated.
- Trusted device persistence: deferred until handshake/auth proof and spaceKey transfer are connected.
- Invitation one-time consumption: deferred because there is no pairing session lifecycle yet.
- SpaceKey transfer to Harmony HUKS: deferred until HUKS/CryptoFramework integration and real pairing handshake are ready.
- Formal WebSocket session lifecycle integration: still pending beyond existing transport frame processor tests.

## Context for Resuming Agent

## Important Context

The latest committed state already includes the desktop and Harmony pairing work described above. `git status --short` should show only this handoff file as untracked unless the user has changed files after this document. Do not regenerate or expose real invitations in the handoff or chat. The invitation fixture in tests is synthetic and safe, but avoid copying full invitation strings into user-facing messages unless necessary. Desktop safe-copy intentionally writes to system clipboard with suppression so the monitor ignores that write. Harmony import intentionally does not write RDB, trusted devices, history, or secrets.

## Assumptions Made

- The desktop invite URI format is currently `eggclip://pair?p=<base64url-json-payload>`.
- Invitation TTL remains 5 minutes.
- Pairing secret remains 32 bytes.
- Issuer identity public key remains Ed25519 32-byte base64url.
- Harmony input import can live in Devices page until a fuller pairing flow exists.
- Current warnings from Harmony hvigor about pasteboard permission and possible thrown exceptions are existing project warnings and not blockers for this work.

## Potential Gotchas

- Harmony ArkTS object spread is rejected; use explicit object construction.
- Do not use a normal desktop clipboard write for invitation safe copy; it can be monitored and saved as history.
- Do not silently read Harmony clipboard; Harmony clipboard access must remain user-triggered and compatible with PasteButton/security constraints.
- Do not persist pairing secrets in SQLite/RDB or logs.
- Desktop `copy_pairing_invitation` currently validates structure but does not verify invitation is still in a persisted invitation registry. One-time consumption is not implemented.
- Harmony confirmation code depends on raw decoded JSON bytes. Re-serializing JSON can change the code if field order/format changes.
- `create_handoff.py` may fail on Windows if Python uses GBK; set `PYTHONUTF8=1` before running handoff scripts.

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`.
- Desktop validation:
  - `cargo fmt -- --check`
  - `cargo check`
  - `cargo test`
  - `pnpm check`
  - `pnpm test`
  - `pnpm build`
- Harmony validation:
  - `hvigorw.bat test --no-daemon`
  - `hvigorw.bat assembleHap --no-daemon`
- Handoff tooling:
  - `C:\Users\caozhipeng\.agents\skills\session-handoff\scripts\create_handoff.py`
  - `C:\Users\caozhipeng\.agents\skills\session-handoff\scripts\validate_handoff.py`

### Active Processes

- No long-running dev server was intentionally left running.
- No `pnpm tauri dev` session was started during handoff creation.

### Environment Variables

- `JAVA_HOME` used for Harmony validation.
- `DEVECO_SDK_HOME` used for Harmony validation.
- `Path` temporarily prepended with DevEco JBR bin for Harmony validation.
- `PYTHONUTF8` used to run handoff scripts safely on Windows.

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`
- Previous handoff: `.claude/handoffs/2026-06-30-115608-eggclip-recent-endpoint-history-clear.md`
- Latest pairing commits:
  - `875ba77 feat: 添加配对邀请生成功能`
  - `51acfb3 feat: 添加安全复制配对邀请功能`
  - `457e734 feat: 实现配对邀请解析与UI展示`

---

**Security Reminder**: Handoff intentionally omits real invitation strings, keys, certificate material, passwords, and local signing material.
