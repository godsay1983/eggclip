# Handoff: EggClip pairing invitation lifecycle and Harmony validation

## Session Metadata

- Created: 2026-07-04 20:55:38
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: roughly one focused continuation session after the 2026-07-04 pairing import handoff

### Recent Commits (for context)

- c85ee87 feat: 实现邀请消息的字段长度和边界校验
- 3c8ea28 feat: 添加后台清理过期配对邀请功能
- fa81c42 feat: 在配对邀请中增加设备名称字段，用于UI展示
- 9dd9693 feat: 创建邀请前自动过期之前的活跃邀请
- c91a7be feat: 接入默认同步空间幂等初始化并优化邀请按钮样式

## Handoff Chain

- **Continues from**: [2026-07-04-163315-eggclip-harmony-pairing-invite-import.md](./2026-07-04-163315-eggclip-harmony-pairing-invite-import.md)
  - Previous title: EggClip pairing invitation generation, safe copy, and Harmony import parsing
- **Supersedes**: None

Review the previous handoff first if you need the full path that led to pairing invitation generation, safe copy, and Harmony import parsing.

## Current State Summary

EggClip is currently in the pairing invitation phase. Desktop can create a default sync space, generate a 5-minute high-entropy `eggclip://pair` invitation, safely copy it without saving the invitation to local history, include an issuer display name for UI confirmation, register the invitation in SQLite, reject local misuse cases, and sweep expired active invitations in the background. Harmony can import the invitation through input text or PasteButton, parse it in memory only, display the issuer device name or fallback short fingerprint, validate key fields and bounds, and move to an in-memory pending state after manual confirmation code acknowledgement. Formal secure pairing, QR rendering/scanning, trusted device persistence, and authenticated sync are still pending.

## Important Context

Parsed invitations, mDNS discovery, POC WebSocket links, and issuer display names are not trust. Desktop invitation generation and Harmony invitation parsing are only bootstrap steps. The next implementation must keep invitation import memory-only on Harmony until formal secure pairing verifies identities, consumes the invitation, receives `spaceKey`, and persists a trusted device. Do not log invitation strings, pairing secrets, raw clipboard content, digests, private keys, signing material, or full protocol frames.

## Immediate Next Steps

1. Implement desktop QR rendering for the existing `eggclip://pair` invitation string and document the QR dependency/platform choice.
2. Add Harmony scan import entry that feeds scanned text into the existing `PairingStore.importInvitationText` path.
3. Begin formal secure pairing by connecting invitation consumption to authenticated handshake, identity transcript validation, and trusted-device persistence.

## Codebase Understanding

### Architecture Overview

EggClip remains split into Tauri desktop, HarmonyOS ArkTS, and shared protocol fixtures. Desktop Rust owns system resources, local SQLite, credentials, invitation lifecycle, clipboard integration, transport, and Tauri commands. Desktop Svelte only calls typed APIs and displays state. Harmony `pages/` compose UI, `store/` owns observable state transitions, and `services/` contain parsing, transport, clipboard, crypto, pairing, and sync logic. Pairing invitation parsing is intentionally not the final trust decision: mDNS and invitation fields are UX and bootstrap inputs; identity, transcript validation, and `spaceKey` delivery must happen later in the secure pairing flow.

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop phase plan | H3 pairing items now note background expiry cleanup is complete; remote import and formal consume entry remain pending. |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony phase plan | H4 invitation import now marks field length validation and issuer display as done; scan import remains pending. |
| `desktop/src-tauri/src/pairing/mod.rs` | Desktop sync space and pairing invitation domain logic | Generates invitation payload, validates safe copy, consumes local invitation skeleton, sweeps expired invitations, and has unit tests. |
| `desktop/src-tauri/src/storage/repositories.rs` | SQLite repository layer | Contains `PairingInvitationRepository` with active, consumed, expired invitation state operations. |
| `desktop/src-tauri/src/lib.rs` | Tauri app assembly | Starts clipboard monitor and pairing invitation expiry background task during setup. |
| `harmony/entry/src/main/ets/services/pairing/PairingInvitationService.ets` | Harmony invitation parser | Parses `eggclip://pair?p=...`, validates fields, builds display summary, and never persists invitation material. |
| `harmony/entry/src/main/ets/store/PairingStore.ets` | Harmony pairing UI state | Keeps parsing/import/confirmation state in memory only. |
| `harmony/entry/src/main/ets/pages/PairingPage.ets` | Harmony pairing UI | Provides text/PasteButton import, summary display, confirmation code, and pending-state button. |
| `harmony/entry/src/test/LocalUnit.test.ets` | Harmony local unit suite | Includes invitation parsing, bounds, fallback display, and store behavior tests. |

### Key Patterns Discovered

- Rust Tauri commands should validate inputs and delegate to domain functions. Keep business logic in modules such as `pairing`, `sync`, `storage`, and `transport`.
- Repository code uses parameterized SQL only. Keep raw plaintext, invitations, and sensitive materials out of logs and snapshots.
- Pairing invitation fields use `camelCase` wire names via Rust serde and ArkTS interfaces. Protocol-facing additions must update both sides and tests.
- Harmony tests must avoid unsupported ArkTS syntax. Object spread caused `arkts-no-spread`; use explicit helper functions and typed object mutation instead.
- Harmony invitation import must remain memory-only until formal secure pairing persists trusted devices and keys.
- The repo may show `warning: unable to access C:\Users\caozhipeng/.config/git/ignore` under sandboxed Codex runs. It did not block git status, log, or diff commands.

## Work Completed

### Tasks Finished

- [x] Desktop invitation payload now includes issuer device display name for UI confirmation only.
- [x] Desktop invitation summary and Svelte UI show issuer device name plus short public-key fingerprint.
- [x] Harmony parser accepts optional `issuerDeviceName`, validates it, displays it, and falls back to `桌面端 #短指纹` for older invitations.
- [x] Desktop creates new invitations after opportunistically expiring old active invitations.
- [x] Desktop app setup starts a background expiry task that sweeps expired active invitations every 60 seconds.
- [x] Desktop unit test `expiry_sweep_marks_only_elapsed_active_invitations` covers expiry sweep behavior.
- [x] Harmony invitation parser now has an explicit decoded payload byte cap and named issuer-device-name length cap.
- [x] Harmony unit test `rejectsPairingInvitationFieldLengthAndControlBoundaries` covers valid issuer name, overlong issuer name, control characters, and too-large URI.
- [x] Desktop and Harmony TODO documents were updated to reflect the completed subitems.

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src-tauri/src/pairing/mod.rs` | Added issuer display name in invitation payload/summary, local display-name normalization, expiry sweep function, and related tests. | Let Harmony identify the inviting desktop in UI and keep stale invites from staying active. |
| `desktop/src-tauri/src/lib.rs` | Starts pairing invitation expiry background task on app setup. | Make expiry lifecycle automatic after app startup. |
| `desktop/src/lib/api/shell.ts` | Added `issuerDeviceName` DTO mapping. | Keep Svelte state typed and aligned with Tauri command output. |
| `desktop/src/lib/types/shell.ts` | Added `issuerDeviceName` to `PairingInvitationSummary`. | Make frontend state include the issuer display name. |
| `desktop/src/routes/+page.svelte` | Displays issuer device name next to short fingerprint in the invitation card. | Improve manual confirmation context without exposing invitation text. |
| `harmony/entry/src/main/ets/services/pairing/PairingInvitationService.ets` | Added optional issuer device name parsing, validation, payload size cap, display fallback, and constants. | Bound invitation inputs and support desktop-issued display names. |
| `harmony/entry/src/main/ets/store/PairingStore.ets` | Clones `issuerDeviceName` in pairing summary snapshots. | Preserve immutable snapshot behavior for UI state. |
| `harmony/entry/src/main/ets/pages/PairingPage.ets` | Displays issuer device name plus short fingerprint. | Match the desktop payload addition in Harmony confirmation UI. |
| `harmony/entry/src/test/LocalUnit.test.ets` | Added invitation display and field-boundary assertions plus fixture helper. | Lock down parser behavior and ArkTS-compatible fixture generation. |
| `DESKTOP_DEVELOPMENT_TODO.md` | Marked invitation device-name and background expiry subitems complete. | Keep plan current. |
| `HARMONY_DEVELOPMENT_TODO.md` | Marked invitation device-name display and field-length validation complete. | Keep plan current. |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Treat `issuerDeviceName` as optional on Harmony | Require new field, or accept optional with fallback | Optional keeps old generated invitations and fixtures parseable while enabling better UI for new invitations. |
| Do not use issuer device name for trust | Include in trust transcript, or display-only | Device names are user-facing labels and not cryptographic identity. Identity must remain bound by public keys and transcript later. |
| Use periodic desktop expiry sweep plus opportunistic cleanup | Only clean when generating invite, only periodic task, or both | Both keeps stale records bounded even when no new invitation is generated and keeps generation path robust. |
| Add payload byte cap in Harmony parser | Rely only on URI length, or also bound decoded payload | Decoded size cap gives a clear internal boundary and explicit test coverage. |
| Avoid QR dependency in this session | Add QR library now, or defer QR rendering/scanning | The session focused on pairing invitation correctness and validation. QR work needs separate UI and possibly dependency choice. |

## Pending Work

### Immediate Next Steps

1. Implement desktop QR rendering for the existing `eggclip://pair` invitation string, preferably with a small reviewed dependency or a shared local generator decision documented in TODO.
2. Add Harmony scan import entry using an approved system scan/safe QR component, feeding scanned text into the existing `PairingStore.importInvitationText` path.
3. Start formal secure pairing: consume `invitationId + pairingSecret` over an authenticated handshake path, bind space/device identity in transcript, and persist trusted device only after success.

### Blockers/Open Questions

- [ ] QR rendering/scanning dependency choice is unresolved. Need decide whether to add a small QR package, use platform APIs, or implement local QR logic.
- [ ] Formal pairing needs protocol-level handshake integration between desktop and Harmony, not just invitation parsing.
- [ ] Harmony CryptoFramework/HUKS real Ed25519, X25519, HKDF, and AES-GCM integration still needs platform validation, preferably on device.
- [ ] Desktop background expiry task currently silently ignores DB/time/path errors to avoid leaking sensitive data or noisy logs. Decide later whether to expose sanitized diagnostics.

### Deferred Items

- Desktop QR rendering: deferred because invitation lifecycle and parser validation were prioritized first.
- Harmony scan import: deferred until QR rendering and platform scan component choice are clear.
- Trusted device persistence and key exchange: deferred because secure handshake/session lifecycle must be designed and connected first.
- Device rename/remove and key rotation: deferred until trusted device records are created by formal pairing.

## Context for Resuming Agent

### Important Context

The codebase is still intentionally short of real secure pairing. Do not treat parsed invitations, mDNS discovery, POC WebSocket connections, or issuer device names as trust. The safe current state is: desktop creates and registers bounded invitations; Harmony parses them in memory and can show a manual confirmation code; pressing “确认码一致，继续配对” only enters a pending state and does not create a trusted device, save invitation material, or receive `spaceKey`. Keep this boundary intact until the formal handshake consumes the invitation and verifies identities.

The latest committed state before this handoff includes commits through `c85ee87 feat: 实现邀请消息的字段长度和边界校验`. At handoff creation, the only untracked file should be this handoff document itself. If the next agent sees uncommitted code changes besides this file, inspect them before continuing.

### Assumptions Made

- Windows remains the only committed v1 desktop platform.
- HarmonyOS target remains SDK 6.1.1(24), compatible SDK 6.1.0(23).
- Invitations are valid for 5 minutes and contain a 256-bit pairing secret.
- Default sync space is acceptable for development until full space/device management is implemented.
- `issuerDeviceName` is for display only and can be absent in old invitations.

### Potential Gotchas

- Do not log invitation strings, pairing secrets, raw clipboard content, content digests, private keys, or full frames.
- Harmony `PasteButton` is required for system clipboard read authorization; do not replace it with a normal button.
- ArkTS does not allow object spread in these tests; use explicit helper functions.
- `harmony/build-profile.json5` may contain local signing configuration. Do not expose or copy protected material.
- Desktop copy invitation uses clipboard suppression to avoid saving the invitation in local history; preserve that behavior if refactoring.
- The background expiry sweep uses app data DB path and runs inside Tauri async runtime. It updates state only; no user-facing notification was added.

## Environment State

### Tools/Services Used

- PowerShell from `D:\Develop\eggclip`.
- Python with `PYTHONUTF8` enabled for session-handoff scripts.
- Desktop Rust checks:
  - `cargo fmt -- --check`
  - `cargo check`
  - `cargo test`
- Desktop frontend checks used in recent pairing UI changes:
  - `pnpm check`
  - `pnpm test`
  - `pnpm build`
- Harmony checks:
  - `hvigorw.bat test --no-daemon`
  - `hvigorw.bat assembleHap --no-daemon`

### Active Processes

- No dev server, watcher, Tauri dev process, or Harmony emulator process was intentionally left running by the agent.

### Environment Variables

- `PYTHONUTF8`
- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`
- Previous handoff: `.claude/handoffs/2026-07-04-163315-eggclip-harmony-pairing-invite-import.md`

---

**Security Reminder**: This document intentionally avoids real invitation strings, secrets, certificate material, private keys, raw clipboard samples, and full protocol frames.
