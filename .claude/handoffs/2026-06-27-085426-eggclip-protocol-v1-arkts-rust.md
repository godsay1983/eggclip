# Handoff: EggClip D1/H1 POC 验收完成与 v1 共享协议 Rust/ArkTS 基线

## Session Metadata

- Created: 2026-06-27 08:54:26
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: 约 4 小时，完成 D1/H1 手动验收确认、共享协议定义、桌面 Rust 协议解析和 HarmonyOS ArkTS 协议解析。
- Current HEAD: `4f38b85`
- Upstream: `origin/main` 同样位于 `4f38b85`

### Recent Commits

- `4f38b85 feat: 完成HarmonyOS端共享协议v1模型与测试向量消费`
- `7db11e1 feat: 桌面Rust实现v1协议类型并接入测试向量`
- `dc4493a feat: 完成EggClip v1共享协议定义，包含schema、测试向量和验证脚本`
- `dbdb29b chore: 在Cargo.toml中添加默认运行目标`
- `1a3e91d feat: 新增POC帧探针脚本和剪贴板标记样本工具，重构诊断记录逻辑并更新文档`

## Handoff Chain

- Continues from: [2026-06-24-000816-eggclip-poc-privacy-and-frame-diagnostics.md](./2026-06-24-000816-eggclip-poc-privacy-and-frame-diagnostics.md)
  - Previous title: EggClip D1/H1 剪贴板隐私与安全帧诊断完成
- Supersedes: Previous handoff's open risk that D1/H1 hand validation lacked confirmation. The user has now confirmed manual testing passed, and `docs/MANUAL_REGRESSION.md` is fully checked.

## Current State Summary

EggClip has moved past the D1/H1 technical POC gate. The Windows and HarmonyOS manual POC checks are recorded as passed in `docs/MANUAL_REGRESSION.md`, including clipboard privacy markers, POC frame diagnostics, mDNS lifecycle, foreground/background cleanup, PasteButton send, user-triggered copy, and LAN WebSocket behavior. The next stage has started: `protocol/` now contains v1 protocol documentation, schema, initial cross-language fixtures, and a lightweight fixture validator. Desktop Rust and HarmonyOS ArkTS both implement the v1 envelope/message/ciphertext/hello/clipboard item parsing baseline and reject unknown versions plus invalid authentication boundaries. The working tree is clean except this new handoff file.

## Codebase Understanding

## Architecture Overview

EggClip is a monorepo with two independent clients and a shared protocol contract. The desktop app is Tauri 2 + Svelte 5 + Rust under `desktop/`; HarmonyOS is ArkTS/ArkUI under `harmony/`; cross-language protocol facts live under `protocol/`. Runtime code is not shared between Rust and ArkTS. The shared contract is documentation, schema, and test vectors. Current WebSocket POC `clipboardText` frames remain unauthenticated development plumbing and must not be treated as the final protocol. The formal v1 protocol envelope gates plaintext handshake messages before authentication and encrypted business frames after authentication.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `protocol/README.md` | v1 protocol narrative specification | Defines envelope, state machine, auth gate, message types, size limits, sync semantics and compatibility rules |
| `protocol/v1.schema.json` | JSON Schema for v1 envelope and core payload definitions | Source of field names and structural constraints for implementations |
| `protocol/test-vectors/` | Shared fixture directory | Rust and ArkTS tests currently mirror these fixtures; crypto byte vectors are still pending |
| `protocol/scripts/validate-fixtures.mjs` | Lightweight Node fixture checker | Verifies current JSON fixtures without adding package dependencies |
| `desktop/src-tauri/src/protocol/mod.rs` | Desktop Rust v1 protocol model/parser | Parses envelope, validates hello/clipboard item, enforces unknown version and auth-boundary rejection |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | HarmonyOS ArkTS v1 protocol model/parser | ArkTS counterpart for envelope, ciphertext, hello and clipboard item parsing |
| `harmony/entry/src/test/LocalUnit.test.ets` | HarmonyOS unit tests | Covers H1 boundaries and v1 protocol parsing/rejection cases |
| `docs/MANUAL_REGRESSION.md` | Manual POC regression record | All D1/H1 manual checks are currently marked passed |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop planning fact source | D1 current status and D3 protocol status were updated |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony planning fact source | H1 current status and ArkTS protocol baseline were updated |
| `README.md` | Project status and next-step summary | Reflects POC completion and current protocol-development status |

### Key Patterns Discovered

- Keep POC transport separate from formal protocol. The desktop transport module still handles temporary untrusted `clipboardText`; formal protocol parsing lives in the desktop protocol module.
- Rust can use richer enum deserialization and `serde_json::Value`; ArkTS needs stricter, more explicit parsing because recursive JSON aliases, `value is Type` guards, `Object.values(Enum)`, and implicit `unknown` catches are not accepted by the Harmony compiler.
- Cross-language protocol work should start from fixtures and constants before wiring transport, crypto, storage or UI.
- Protocol errors should be fixed categories or enum codes; user-facing Chinese text can be mapped later at UI boundaries.
- The current shared fixtures are schema/parsing fixtures only. They are not crypto vectors and do not prove encryption compatibility.
- Manual POC diagnostics must never log or display clipboard body, digest, invitation, key material or full frame data.

## Work Completed

### Tasks Finished

- [x] Completed D1/H1 manual regression confirmation and updated current-state documentation.
- [x] Created `protocol/README.md` with v1 state machine, message types, envelope, auth gate, encrypted payload shape, clipboard item, sync heads and compatibility rules.
- [x] Created `protocol/v1.schema.json`.
- [x] Created initial `protocol/test-vectors/` fixtures for handshake, sync and rejection cases.
- [x] Created `protocol/scripts/validate-fixtures.mjs` and verified it with `node .\protocol\scripts\validate-fixtures.mjs`.
- [x] Added desktop Rust protocol module with constants, message types, envelope parser, ciphertext frame, hello payload, clipboard item and sync heads validation.
- [x] Added Rust fixture tests for valid client hello, encrypted item live, clipboard item, unknown version rejection, post-auth plaintext rejection, unknown type rejection and pre-auth ciphertext rejection.
- [x] Added HarmonyOS ArkTS protocol model/parser with equivalent constants and parsing/rejection behavior.
- [x] Added HarmonyOS unit tests for the ArkTS protocol model.
- [x] Fixed the test-vector clipboard item `contentLength` from 18 to 17 to match actual UTF-8 bytes.
- [x] Fixed Tauri dev ambiguity from the helper binary by adding `default-run = "eggclip"` to `desktop/src-tauri/Cargo.toml`.

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `protocol/README.md` | Added v1 protocol specification | Establish one cross-client source for protocol behavior before crypto/storage integration |
| `protocol/v1.schema.json` | Added envelope and core payload schema | Provide structural contract for Rust/ArkTS implementations |
| `protocol/test-vectors/**` | Added initial valid/reject fixtures and crypto placeholder | Start shared fixture workflow without premature crypto bytes |
| `protocol/scripts/validate-fixtures.mjs` | Added dependency-free fixture validator | Allows quick protocol fixture sanity check on Windows |
| `desktop/src-tauri/src/protocol/mod.rs` | Added Rust v1 parser and tests | Desktop protocol foundation |
| `desktop/src-tauri/src/lib.rs` | Exposed `protocol` module | Make protocol module part of library crate tests |
| `desktop/src-tauri/Cargo.toml` | Added `default-run = "eggclip"` | Keep `pnpm tauri dev` working after adding helper binary |
| `desktop/scripts/poc-frame-probe.ps1` | Added POC frame probe script | Supports manual safety-frame diagnostics |
| `desktop/src-tauri/src/bin/clipboard_marker_sample.rs` | Added Windows clipboard marker sample tool | Supports privacy marker manual regression |
| `desktop/src-tauri/src/transport/mod.rs` | Refactored diagnostic state and added tests | POC diagnostics became testable metadata-only state |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | Added ArkTS v1 parser/model | Harmony protocol foundation |
| `harmony/entry/src/test/LocalUnit.test.ets` | Added ArkTS protocol tests | Ensures ArkTS rejects/accepts same baseline fixtures |
| `docs/MANUAL_REGRESSION.md` | Recorded D1/H1 manual checks as passed | Captures user's manual test confirmation |
| `README.md`, `DESKTOP_DEVELOPMENT_TODO.md`, `HARMONY_DEVELOPMENT_TODO.md` | Updated status and next steps | Align docs with POC completion and protocol baseline |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Treat D1/H1 manual tests as passed only after user confirmation | Keep deferred; infer from docs; wait for explicit confirmation | User explicitly stated manual tests passed, and the regression file is fully checked |
| Build protocol foundation before storage or UI work | Start D2/H2 data model first; extend POC transport; define protocol first | Formal protocol and auth gate prevent POC JSON from leaking into product architecture |
| Keep Rust and ArkTS protocol implementations separate | Share runtime code; generate ArkTS from Rust; hand-write both against fixtures | AGENTS.md requires Rust and ArkTS implement separately and share schema/test vectors only |
| Use lightweight Node fixture validator | Add npm dependency; rely only on Rust tests; skip validator | Current repo already has Node; no dependency churn; catches obvious fixture drift |
| Keep crypto vectors as TODO placeholders | Fake vectors now; omit crypto folder; add placeholder | Avoid misleading byte-for-byte claims before actual algorithm implementation |
| Implement ArkTS JSON parsing without advanced type guards | Use recursive JSON aliases and `value is Type`; use explicit casts and helper functions | Harmony ArkTS compiler rejects recursive aliases and TypeScript-style type predicates |

## Pending Work

## Immediate Next Steps

1. Create deterministic crypto test vectors under `protocol/test-vectors/crypto/` for Ed25519, X25519, HKDF-SHA-256, AES-256-GCM, AEAD tamper rejection and replay/counter rejection.
2. Add desktop Rust `crypto/` module for device identity and handshake primitives, consuming the new vectors first.
3. Verify HarmonyOS SDK 6.1.1 CryptoFramework/HUKS APIs for Ed25519, X25519, HKDF and AES-GCM, then add ArkTS tests against the same vectors.
4. After crypto vectors pass on both sides, start local identity persistence: desktop system credentials first, Harmony HUKS or equivalent secure storage second.

### Blockers/Open Questions

- [ ] Need concrete HarmonyOS CryptoFramework/HUKS API verification for Ed25519, X25519, HKDF and AES-GCM on SDK 6.1.1(24).
- [ ] Need decide how to generate and store deterministic test-only crypto vectors without introducing real secrets or production material.
- [ ] Need choose Rust crypto crates and confirm MSRV 1.85 compatibility before adding dependencies.
- [ ] Historical Harmony signing material risk from commit `74d9bb1` remains a project-level security task; do not print or copy signing material.

### Deferred Items

- D2/H2 persistent data, SQLite/RDB, retention and repositories are still pending. Protocol/crypto foundation is being built first.
- Formal transport integration is deferred until auth/session encryption can wrap business messages.
- Automatic discovery/ConnectionManager, sync heads range requests and batch backfill are still D4/H5+ work.
- Packaging, code signing and release checklists are still later phases.

## Context for Resuming Agent

## Important Context

EggClip v1 is a LAN-only `text/plain` clipboard sync product. Windows desktop may eventually auto-write authenticated online `ITEM_LIVE` events; HarmonyOS must stay foreground-only and must use real `PasteButton` for sending plus user-triggered copy for received text. The POC WebSocket `clipboardText` JSON is still unauthenticated and must remain user-triggered; do not extend it into production protocol. Formal v1 protocol work has started in `protocol/`, `desktop/src-tauri/src/protocol/mod.rs`, and `harmony/entry/src/main/ets/models/ProtocolModels.ets`. D1/H1 manual testing is now considered passed per user confirmation and `docs/MANUAL_REGRESSION.md`, but crypto, pairing, storage and official sync are not implemented. The next agent should not redo POC diagnostics; move forward to crypto vectors and identity primitives.

## Assumptions Made

- User's statement "手动测试都过了" refers to the D1/H1 manual regression checklist in `docs/MANUAL_REGRESSION.md`.
- Current commits through `4f38b85` are already on `origin/main`.
- The repository should stay on `main`; no branch, commit or push was requested during handoff creation.
- `hvigorw test` Pasteboard permission warning is expected because production send path uses ArkUI `PasteButton`; do not try to request ordinary `READ_PASTEBOARD` as the product path.
- Crypto vectors must be synthetic test-only material, not production keys, real invitations, real clipboard content or signing material.

## Potential Gotchas

- Adding any second Rust binary under `desktop/src-tauri/src/bin/` requires `default-run = "eggclip"` to keep `pnpm tauri dev` working. This is already set.
- ArkTS has stricter rules than TypeScript: avoid `any`/`unknown`, recursive type aliases, TypeScript type predicates like `value is Foo`, and enum reflection patterns that trigger class-as-object warnings.
- `protocol/scripts/validate-fixtures.mjs` is a lightweight semantic check, not a full JSON Schema validator.
- Current `contentDigest` fixture values are placeholder Base64URL strings, not HMAC-SHA-256 results.
- Rust protocol `parse_envelope` validates envelope and auth gate, not full schema `additionalProperties` parity yet.
- Harmony protocol tests embed compact JSON fixture strings instead of reading files from `protocol/test-vectors/`; treat them as mirrored fixtures until a robust test-resource loading path is added.
- `docs/MANUAL_REGRESSION.md` line about "接入认证 ITEM_LIVE" is a POC suppression verification note; real authenticated `ITEM_LIVE` auto-write is still not integrated.
- Do not introduce telemetry, cloud sync, account systems, S3, public relay, image/file sync or background Harmony clipboard reads.

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Rust/Cargo, Tauri 2, Svelte 5, pnpm
- Node.js for `protocol/scripts/validate-fixtures.mjs`
- DevEco Studio JBR and HarmonyOS SDK 6.1.1(24)
- `session-handoff` scripts from `C:\Users\caozhipeng\.agents\skills\session-handoff`

### Active Processes

- No dev server, Tauri process, Cargo watcher, Node watcher or Harmony build daemon needs to be carried forward.
- Handoff creation left only this new handoff file untracked.

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Validation Snapshot

Current validation rerun during handoff creation:

- `cargo test` in `desktop/src-tauri`: passed, 30 tests.
- `node .\protocol\scripts\validate-fixtures.mjs`: passed, output `protocol fixtures ok`.
- `hvigorw.bat test --no-daemon` in `harmony`: passed.
- Harmony test still emits the expected Pasteboard permission warning at `ClipboardBridgeService.ets:25:42`.

Recent known checks from the completed work:

- `cargo fmt -- --check`: passed.
- `cargo check`: passed.
- `pnpm release:check`: previously passed after POC tooling and `default-run` fix.

Git snapshot at handoff:

- Branch: `main`
- HEAD: `4f38b85`
- Upstream: `origin/main` at `4f38b85`
- `git status --short --branch`: clean except untracked `.claude/handoffs/2026-06-27-085426-eggclip-protocol-v1-arkts-rust.md`

## Related Resources

- `AGENTS.md`
- `README.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `docs/EggClip最佳实现方案.md`
- `docs/MANUAL_REGRESSION.md`
- `protocol/README.md`
- `protocol/v1.schema.json`
- `protocol/test-vectors/README.md`
- `protocol/test-vectors/crypto/README.md`
- `protocol/scripts/validate-fixtures.mjs`
- `desktop/src-tauri/src/protocol/mod.rs`
- `harmony/entry/src/main/ets/models/ProtocolModels.ets`
- `harmony/entry/src/test/LocalUnit.test.ets`
- `.claude/handoffs/2026-06-24-000816-eggclip-poc-privacy-and-frame-diagnostics.md`

---

Security reminder: rerun the validator after any edit. Never add signing material, passwords, real clipboard samples, invitations, keys, digests or complete runtime network frames.
