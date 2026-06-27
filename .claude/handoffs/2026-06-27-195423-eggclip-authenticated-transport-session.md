# Handoff: EggClip authenticated transport session integration

## Session Metadata

- Created: 2026-06-27 19:54:23
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: about 1 development turn after protocol AEAD frame work

### Recent Commits (for context)

- fae88c5 feat: 集成认证传输会话到Rust和ArkTS传输层
- e037675 feat: 实现协议加密信封构建与解密，添加规范AAD和方向nonce校验
- ba91bef feat: 为入站会话添加重放保护，拒绝重复messageId和非递增sessionCounter
- c02f818 feat: 新增协议会话状态机认证门控
- d6027c8 feat: 实现AUTH_PROOF握手消息，规范转录本绑定和Ed25519签名验证

## Handoff Chain

- Continues from: [2026-06-27-085426-eggclip-protocol-v1-arkts-rust.md](./2026-06-27-085426-eggclip-protocol-v1-arkts-rust.md)
  - Previous title: EggClip D1/H1 POC 验收完成与 v1 共享协议 Rust/ArkTS 基线
- Supersedes: none

## Current State Summary

EggClip has moved from shared protocol primitives into the first formal transport-session integration layer. The desktop Rust side now has an `AuthenticatedTransportSession` that can serialize encrypted business frames, increment outbound session counters, parse inbound formal protocol frames, apply the authenticated session gate, apply replay protection, and decrypt payloads before sync/storage dispatch. The HarmonyOS ArkTS side now has a matching `ProtocolTransportSession` boundary that parses formal frames and applies authenticated state/replay gating, but it intentionally does not perform real AES-GCM decryption yet because CryptoFramework/HUKS integration remains pending. The working tree is clean except for this handoff file.

## Codebase Understanding

### Architecture Overview

EggClip still has two transport paths:

- POC path: unauthenticated `clipboardText` JSON used by current desktop/Harmony demo UI and manual LAN testing. This must not be promoted to production semantics.
- Formal protocol path: versioned envelopes, authenticated session state, replay guard, AEAD encrypted business payloads and protocol-level frame processors. This path is now implemented as pure logic but is not yet wired into live WebSocket connection lifecycle.

The desktop transport code exports the new formal session processor from `transport/mod.rs` while preserving the POC commands and events. The HarmonyOS code adds a separate service under `services/transport/ProtocolTransportSession.ets`, again without disturbing the existing POC WebSocket service. This separation is deliberate: the next step is wiring, not replacing the POC behavior blindly.

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/src-tauri/src/protocol/mod.rs` | Rust protocol types, parsing, AEAD envelope build/decrypt, session gate and replay guard | Added encrypted envelope serialization and authenticated constructors used by formal transport session |
| `desktop/src-tauri/src/transport/session.rs` | Rust authenticated transport session pure logic | New central boundary for formal WebSocket frame processing after handshake/auth |
| `desktop/src-tauri/src/transport/mod.rs` | Existing Rust POC WebSocket transport | Re-exports `AuthenticatedTransportSession`; current POC runtime is still active and not yet migrated |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | ArkTS protocol parser, session gate and replay guard | Added initial-state constructors so transport can start at authenticated state after handshake |
| `harmony/entry/src/main/ets/services/transport/ProtocolTransportSession.ets` | ArkTS formal transport frame processor | New formal receive boundary for parsed encrypted envelopes and replay/state checks |
| `harmony/entry/src/test/LocalUnit.test.ets` | Harmony unit tests | Covers formal transport acceptance, duplicate rejection and POC plaintext rejection |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop plan | Updated checked subtasks for authenticated transport session logic |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony plan | Updated checked subtasks for ArkTS formal transport entry logic |

### Key Patterns Discovered

- Keep POC and formal protocol paths separate. POC accepts `{"kind":"clipboardText"}`; formal protocol requires v1 envelopes and authenticated session gating.
- Transport should not decide clipboard write policy. It should only parse, gate, decrypt and hand payloads to sync later.
- AEAD failures, wrong direction/key id, wrong nonce, replay and duplicate message ID should be rejected before exposing payloads to sync or storage.
- ArkTS currently mirrors rules and validates structure; real platform cryptography is a separate HUKS/CryptoFramework task.
- TODO updates should split broad work into sub-checkboxes and mark completed subtasks, instead of appending progress prose to an unchecked parent only.

## Work Completed

### Tasks Finished

- [x] Added Rust encrypted envelope serialization through `serialize_encrypted_envelope`.
- [x] Added Rust authenticated session constructors for protocol gate/inbound session.
- [x] Added Rust `AuthenticatedTransportSession` with outbound encryption, inbound parse/gate/replay/decrypt and `sessionCounter` increment.
- [x] Added Rust tests for encrypted transport round-trip, duplicate-frame rejection and POC plaintext rejection.
- [x] Added ArkTS initial-state constructors for `ProtocolSessionGate` and `ProtocolInboundSession`.
- [x] Added ArkTS `ProtocolTransportSession` to parse formal frames and apply authenticated gate/replay checks.
- [x] Added ArkTS tests for accepting encrypted formal frames, rejecting duplicates and rejecting POC plaintext JSON.
- [x] Updated desktop and Harmony TODO files with checked subtasks for this milestone.
- [x] Ran full validation suite and confirmed existing Harmony warnings only.

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src-tauri/src/protocol/mod.rs` | Added `OutboundEncryptedEnvelope`, `serialize_encrypted_envelope`, `ProtocolSessionGate::authenticated`, `ProtocolInboundSession::authenticated` | Allows formal transport session to serialize encrypted frames and start from post-handshake authenticated state |
| `desktop/src-tauri/src/transport/mod.rs` | Added `mod session` and public re-export of `AuthenticatedTransportSession`/`TransportFrameError` | Exposes formal transport session while preserving existing POC commands |
| `desktop/src-tauri/src/transport/session.rs` | New file implementing authenticated transport frame processor and tests | Provides the first formal transport/session boundary before live WebSocket wiring |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | Added constructors with initial state for `ProtocolSessionGate` and `ProtocolInboundSession` | Lets Harmony formal transport enter authenticated state after future handshake completion |
| `harmony/entry/src/main/ets/services/transport/ProtocolTransportSession.ets` | New file implementing ArkTS formal transport frame processor | Provides parse/state/replay boundary before WebSocket service integration and real AES-GCM |
| `harmony/entry/src/test/LocalUnit.test.ets` | Added `ProtocolTransportSession` tests | Ensures formal transport behavior is covered by hvigor unit tests |
| `DESKTOP_DEVELOPMENT_TODO.md` | Checked authenticated transport session processor and counter/replay subtasks | Keeps plan accurate and avoids unchecked progress-only notes |
| `HARMONY_DEVELOPMENT_TODO.md` | Checked ArkTS transport session replay and POC plaintext rejection subtasks | Keeps mobile plan accurate while leaving true WebSocket and crypto work unchecked |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Add pure transport-session processors before live WebSocket rewiring | Directly replace POC WebSocket path, or add pure logic first | Pure logic is testable, keeps POC demo stable, and avoids mixing unauthenticated `clipboardText` with formal encrypted protocol |
| Rust formal session performs real AEAD decrypt; ArkTS only gates/parses for now | Try to fake ArkTS decrypt, or wait for CryptoFramework/HUKS | Faking crypto would create false confidence. Harmony TODO explicitly keeps real AES-GCM pending |
| Start authenticated sessions through explicit constructors | Mutate private fields in tests, or expose broad setters | Explicit constructors encode the intended post-handshake boundary with less state leakage |
| Treat TODO parent tasks as incomplete until live WebSocket wiring is done | Mark entire parent complete, or check only completed subtasks | Parent tasks include real lifecycle integration, so only pure-logic subtasks were checked |

## Pending Work

## Immediate Next Steps

1. Wire `AuthenticatedTransportSession` into the desktop live WebSocket receive/send path after a real or temporary authenticated-session bootstrap. Do not feed unauthenticated POC `clipboardText` through it.
2. Wire Harmony `ProtocolTransportSession` into `WebSocketTransportService` formal receive path, behind an explicit authenticated state, while keeping the POC path separate.
3. Implement the missing handshake/session lifecycle pieces: production ephemeral X25519 generation, AUTH_PROOF verification, HKDF transcript input, and construction of directional session keys from real handshake state.
4. After formal frames reach sync, connect `ITEM_LIVE` to sync policy and only then call desktop `sync::apply_authenticated_live_item` for online live events.
5. Keep TODO documents updated by checking fine-grained subtasks when they are actually wired and tested.

### Blockers/Open Questions

- [ ] Real handshake state is not implemented yet. Need X25519 ephemeral key exchange, AUTH_PROOF verification and HKDF-derived directional keys before production sessions can be established.
- [ ] Harmony real AEAD decrypt is not implemented. Need CryptoFramework/HUKS AES-GCM integration before encrypted business payloads can be exposed to sync.
- [ ] No storage layer yet. `ClipboardItem`, device trust records, spaces, sync heads and RDB/SQLite migrations remain D2/H2 work.
- [ ] Live WebSocket formal path has no session lifecycle owner yet. Need a future ConnectionManager/session manager to own counters, peer identity, reconnect and failure semantics.

### Deferred Items

- Desktop automatic clipboard write from formal `ITEM_LIVE`: deferred until sync engine can distinguish live vs batch and formal frame source is authenticated.
- Real pairing/invitation UI: deferred until identity, HUKS/credential persistence and storage exist.
- mDNS formal discovery replacement: deferred until ConnectionManager exists; current mDNS remains POC-oriented.
- ArkTS platform crypto vector execution: deferred until CryptoFramework/HUKS wrapper is built.

## Context for Resuming Agent

## Important Context

- Current HEAD is `fae88c5 feat: 集成认证传输会话到Rust和ArkTS传输层`. The code changes from the last development turn are already committed; only this handoff file is untracked.
- Do not collapse POC and formal protocol paths. The POC path is intentionally unauthenticated and useful for UI/manual testing, but production sync must use formal v1 envelopes and authenticated session processing.
- `AuthenticatedTransportSession` in Rust is pure logic. It is not currently used by the live WebSocket runtime. Its tests prove frame-level behavior only.
- `ProtocolTransportSession` in ArkTS also is pure logic. It does not decrypt AES-GCM payloads yet; it only parses v1 envelopes, applies authenticated session state and replay checks, and rejects POC plaintext JSON.
- Desktop `sync::apply_authenticated_live_item` is the boundary for auto-writing remote live items to the Windows clipboard. It must only be called for authenticated online `ITEM_LIVE`, never for batch/history or POC frames.
- HarmonyOS must not silently read the clipboard. Sending still has to originate from a real ArkUI `PasteButton` authorization.
- Existing Harmony warnings during build are expected: static Pasteboard permission warning and no signingConfig for default product. Do not treat them as new regressions.

### Assumptions Made

- The repository auto-commits or an external workflow committed the previous turn's code changes; observed clean status plus HEAD `fae88c5` confirms this state.
- It is acceptable to use test-only deterministic keys from `protocol/test-vectors/crypto/session-keys.valid.json` in unit tests only.
- Formal transport wiring should wait for a clear session lifecycle/ConnectionManager owner instead of embedding production state into the POC runtime.
- ArkTS can safely add protocol/session pure logic before platform crypto wrappers, as long as TODO and tests do not claim real decrypt support.

### Potential Gotchas

- `git diff --stat` does not show untracked files unless staged; always check `git status --short` for new files.
- `git diff --check` does not check untracked files. For new files, run an explicit whitespace scan such as `rg -n "\s+$" <new-files>`.
- On Windows, Git may warn that LF will be replaced by CRLF. This was seen and is not by itself a failure.
- Cargo commands may block briefly on package/build directory locks when multiple validations run in parallel.
- Harmony `hvigorw test` may print the Pasteboard permission warning even when tests pass.
- Avoid logging ciphertext body, tag, keys, invitation secrets, HMAC digests or clipboard content. Current tests use synthetic public fixtures and sample strings only.

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Rust/Cargo for desktop backend validation
- pnpm/Vite/SvelteKit for desktop frontend validation
- DevEco Studio bundled JBR and hvigor for Harmony validation
- `session-handoff` skill scripts with `PYTHONUTF8=1`

### Active Processes

- No dev server, watcher or long-running helper was intentionally left running.
- Validation commands were one-shot and completed.

### Environment Variables

- `PYTHONUTF8` was set while running handoff scripts.
- Harmony validation uses `JAVA_HOME`, `DEVECO_SDK_HOME`, and `Path` pointing at DevEco Studio JBR/tools. Do not record secret values.

## Validation Performed

The following checks passed in the last development turn:

- `cargo fmt -- --check`
- `cargo check`
- `cargo test` with 49 Rust tests passing
- `node .\protocol\scripts\validate-fixtures.mjs`
- `pnpm check`
- `pnpm test`
- `pnpm build`
- `hvigorw.bat test --no-daemon`
- `hvigorw.bat assembleHap --no-daemon`
- `git diff --check`
- explicit trailing-whitespace scan for the newly added Rust/ArkTS transport session files

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `protocol/README.md`
- `protocol/test-vectors/`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- Previous handoff: `.claude/handoffs/2026-06-27-085426-eggclip-protocol-v1-arkts-rust.md`

---

Security note: this handoff intentionally references file paths, commit IDs, and validation commands only. It does not include signing material, private keys, invitations, tokens, passwords, clipboard samples from the user, or secret values.
