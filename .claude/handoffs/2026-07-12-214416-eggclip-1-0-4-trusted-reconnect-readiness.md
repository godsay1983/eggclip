# Handoff: EggClip 可信重连就绪修复与双端版本提升

## Session Metadata

- Created: 2026-07-12 21:44:16
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Current commit: `0070615 feat: 可信重连增加空间密钥版本协商与同步就绪状态`
- Working tree: 仅双端版本文件和本 handoff 尚未提交
- Desktop version: `1.0.4`
- HarmonyOS version: `1.0.2` (`versionCode 10002`)

## Handoff Chain

- Continues from: [2026-07-12-182317-eggclip-desktop-1-0-3-expanded-pairing-qr.md](./2026-07-12-182317-eggclip-desktop-1-0-3-expanded-pairing-qr.md)
- Supersedes that handoff for current version and reconnect-readiness state.

## Current State Summary

The initial trusted-reconnect one-way synchronization defect has been implemented and committed in `0070615`. Its root cause was that the desktop resent an unchanged space-key version as `rotation-v1`; HarmonyOS correctly rejected that replay, leaving the authenticated socket open but not ready for outbound live synchronization until a desktop message happened to repair the visible state. The reconnect handshake now binds the HarmonyOS space-key version into the signed context, the desktop only delivers a key when the client is genuinely behind, and HarmonyOS separates `AUTH_OK` from synchronization readiness. Desktop metadata has now been raised from `1.0.3` to `1.0.4`; HarmonyOS metadata has been raised from `1.0.1` to `1.0.2`. Build checks pass, but the new reconnect behavior still needs the phone-and-tablet real-device acceptance cases recorded in the manual regression document.

## Work Completed

- [x] Diagnosed the first-send direction asymmetry after phone and tablet reconnect.
- [x] Added signed trusted reconnect context `trusted-device:<spaceId>:key-v<spaceKeyVersion>`.
- [x] Prevented same-version key replay while preserving delivery to clients that missed a real rotation.
- [x] Rejected a client that claims a key version newer than the desktop space.
- [x] Added HarmonyOS `syncReady` state and `初始化中` / `已就绪` UI distinction.
- [x] Queued PasteButton content created during initialization and submitted it after readiness.
- [x] Kept real-time synchronization available when historical `SYNC_HEADS` persistence is degraded.
- [x] Updated protocol, implementation, platform README, tests, and manual regression documentation.
- [x] Raised desktop version to `1.0.4` in all four version surfaces.
- [x] Raised HarmonyOS version to `1.0.2` and `versionCode` to `10002`.

## Architecture and Decisions

### Reconnect readiness

- `AUTH_OK` proves the peer identity and establishes the session keys; it does not by itself mean clipboard synchronization is ready.
- For a same-version trusted reconnect, the desktop sends `AUTH_OK` followed by `SYNC_HEADS`. HarmonyOS becomes ready only after its local synchronization initialization succeeds.
- If HarmonyOS reports an older key version, the desktop sends `AUTH_OK`, a strictly newer `rotation-v1` delivery, and then `SYNC_HEADS`.
- The key version is part of `pairingContext`, which is included in the signed authentication transcript. It is not accepted as unauthenticated metadata.
- Initial pairing still uses invitation context and receives `pairing-v1`; the key-version reconnect context applies only to already trusted devices.

### Initialization sends

- PasteButton content produced after authentication but before readiness is persisted first and then kept in a short-lived live-send queue.
- The queued payload contains clipboard text in memory and must never be logged. Durable history remains protected by the existing local encryption path.
- `markAuthenticatedActivity` does not promote an initializing reconnect to ready; otherwise a desktop `ITEM_LIVE` racing ahead of `SYNC_HEADS` could strand the initialization queue.

### Versioning

- Desktop and HarmonyOS versions are intentionally independent because desktop received several desktop-only patch releases.
- Desktop version surfaces are `desktop/package.json`, `desktop/src-tauri/Cargo.toml`, `desktop/src-tauri/tauri.conf.json`, and the `eggclip` package in `desktop/src-tauri/Cargo.lock`.
- HarmonyOS release metadata is in `harmony/AppScope/app.json5`; `versionCode` must increase for upgrades.

## Critical Files

| File | Purpose |
|------|---------|
| `desktop/src-tauri/src/transport/mod.rs` | Chooses same-version reconnect versus missed-rotation key delivery and starts authenticated sync. |
| `desktop/src-tauri/src/pairing/mod.rs` | Parses and validates the signed trusted reconnect key-version context. |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Owns authenticated state, synchronization readiness, initialization queue, reconnect, and live-send orchestration. |
| `harmony/entry/src/main/ets/services/pairing/PairingHandshakeDraftService.ets` | Builds the signed trusted reconnect context. |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Shows initialization status and PasteButton send result. |
| `harmony/entry/src/main/ets/pages/PairingPage.ets` | Shows `初始化中` or `已就绪`. |
| `harmony/entry/src/test/LocalUnit.test.ets` | Covers trusted reconnect draft and pre-readiness state. |
| `docs/MANUAL_REGRESSION.md` | Contains the remaining phone/tablet initialization acceptance cases. |
| `protocol/README.md` | Documents the versioned trusted reconnect context and transcript binding. |
| `desktop/package.json` | Desktop JavaScript version `1.0.4`. |
| `desktop/src-tauri/Cargo.toml` | Desktop Rust package version `1.0.4`. |
| `desktop/src-tauri/tauri.conf.json` | Desktop bundle version `1.0.4`. |
| `desktop/src-tauri/Cargo.lock` | Locked EggClip package version `1.0.4`. |
| `harmony/AppScope/app.json5` | HarmonyOS version `1.0.2`, code `10002`. |

## Validation Performed

Before the version-only edits, the reconnect implementation passed:

- Desktop `pnpm check`: 0 errors and 0 warnings.
- Desktop `pnpm test`: 7 tests passed.
- Desktop `pnpm build`: successful.
- Rust `cargo fmt -- --check`: successful.
- Rust `cargo check`: successful.
- Rust `cargo test`: 131 tests passed.
- HarmonyOS `scripts/verify.ps1`: format, lint, type check, unit tests, and `assembleHap` passed; lint retained 7 existing advisory warnings.
- `git diff --check`: successful.

After the version edits:

- Rust `cargo check` compiled `eggclip v1.0.4` successfully.
- HarmonyOS `assembleHap --no-daemon` built `versionName 1.0.2` metadata successfully.

## Important Context

1. Install/build both updated sides before real-device validation. The trusted reconnect context format changed on both sides; testing a new desktop against an older installed HarmonyOS build can fail before authentication.
2. Existing paired devices and keys do not need to be cleared when both builds are updated. The context is generated from the persisted local space-key version at reconnect time.
3. Do not revert to unconditional `rotation-v1` delivery on every reconnect. Same-version rejection was the exact cause of the reported first-send failure.
4. Do not mark synchronization ready on arbitrary authenticated activity. Readiness must follow initial key delivery for pairing or the first synchronization initialization for trusted reconnect.
5. The user wants TODO files to remain fixed plans: complete and check existing items, but do not append incremental implementation notes as new TODO tasks.
6. Do not expose `harmony/build-profile.json5` signing material in logs, handoffs, or chat.
7. No branch, commit, push, installer publication, or release was requested. The five version files and this handoff are intentionally uncommitted.

## Immediate Next Steps

1. Install the newly built HarmonyOS `1.0.2` HAP on both phone and tablet and run desktop `1.0.4`; preserve existing app data and paired-device records.
2. Complete the three unchecked `认证连接初始化` cases in `docs/MANUAL_REGRESSION.md`: both Harmony devices must independently send first without a desktop warm-up message, a PasteButton action during `初始化中` must auto-submit after readiness, and bidirectional first-send must not form a loop.
3. If those pass, check the three manual regression boxes and then continue the remaining release-stage items in both TODO files: platform/network/stability runs, installers/signing, upgrade/rollback, and privacy checks.

## Pending Work

### Manual acceptance

- [ ] Phone and tablet reconnect to a running desktop and each sends first without desktop warm-up traffic.
- [ ] PasteButton tapped during `初始化中` is saved and automatically sent after `已就绪`.
- [ ] Windows-to-HarmonyOS and HarmonyOS-to-Windows independent first-send paths work without loops.
- [ ] Windows autostart behavior is verified across an actual sign-out/sign-in cycle.

### Existing TODO milestones

- [ ] Desktop Windows 10/11, DPI, multi-monitor, firewall, Wi-Fi/sleep switching, and rapid-copy regression.
- [ ] Two-hour dual-side stability run with no synchronization loop storm.
- [ ] Desktop NSIS metadata, code signing, upgrade/uninstall, and rollback checklist.
- [ ] HarmonyOS phone/tablet network, foreground/background, lock screen, pairing-error, PasteButton, Emoji, maximum-text, and continuous-send regression.
- [ ] HarmonyOS formal signing, privacy/permission text, release secret scan, upgrade, and rollback checklist.

## Potential Gotchas

- A same-version reconnect should not receive `SPACE_KEY_ROTATED`; its readiness signal is `SYNC_HEADS`.
- A client behind the desktop key version must receive the newer key before normal historical synchronization.
- A client claiming a future key version is rejected rather than guessed or silently downgraded.
- mDNS only supplies candidate addresses and is never identity authentication.
- Simulator success cannot replace real-device validation for PasteButton, WebSocket lifecycle, HUKS, and network switching.
- Existing ArkTS advisory warnings are known and were present before this milestone; do not confuse them with build failures.

## Environment State

- OS/shell: Windows PowerShell.
- Desktop toolchain: pnpm, SvelteKit, Tauri 2, Rust/Cargo.
- HarmonyOS toolchain: DevEco Studio JBR and SDK, `hvigorw.bat`.
- Relevant environment variable names: `JAVA_HOME`, `DEVECO_SDK_HOME`, `Path`, `PYTHONUTF8`.
- Active development servers: none started by this session.
- Latest committed implementation: `0070615`.
- Uncommitted scope: desktop version surfaces, HarmonyOS version metadata, and this handoff only.

## Related Resources

- [Desktop development plan](../../DESKTOP_DEVELOPMENT_TODO.md)
- [HarmonyOS development plan](../../HARMONY_DEVELOPMENT_TODO.md)
- [Manual regression checklist](../../docs/MANUAL_REGRESSION.md)
- [Best implementation design](../../docs/EggClip最佳实现方案.md)
- [Shared protocol documentation](../../protocol/README.md)
- [Desktop README](../../desktop/README.md)
- [HarmonyOS README](../../harmony/README.md)

---

Security review note: this handoff contains no invitation strings, clipboard content, private keys, signing material, passwords, tokens, or credential values.
