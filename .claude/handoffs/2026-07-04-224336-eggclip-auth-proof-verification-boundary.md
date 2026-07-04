# Handoff: EggClip Harmony AUTH_PROOF verification boundary

## Session Metadata
- Created: 2026-07-04 22:43:36
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: ~1 session focused on Harmony pairing/auth handshake hardening

### Recent Commits (for context)
  - 1c172c1 feat: 提取通用Ed25519验证方法并集成到配对认证验证服务
  - 4775416 feat: 新增PairingAuthProofValidationService及单元测试
  - a80f853 feat: 新增PairingClientHandshakeSessionService，串联客户端握手流程
  - 180b6d6 feat: 实现客户端AUTH_PROOF信封构建，提取SHA256为独立服务
  - 2eb8178 feat: 实现SERVER_HELLO匹配校验与客户端认证转录生成

## Handoff Chain

- **Continues from**: [2026-07-04-205538-eggclip-pairing-invitation-validation.md](./2026-07-04-205538-eggclip-pairing-invitation-validation.md)
  - Previous title: EggClip pairing invitation lifecycle and Harmony validation
- **Supersedes**: None

## Current State Summary

Harmony pairing/auth handshake preparation has advanced from invitation import and CLIENT_HELLO construction to an in-memory client handshake pipeline and AUTH_PROOF validation boundary. The branch currently contains committed work for CLIENT_HELLO frame construction, SERVER_HELLO identity/space validation, AUTH_PROOF frame construction, a reusable SHA-256 utility, client handshake session orchestration, AUTH_PROOF pre-verification checks, and a reusable Ed25519 verification entry point. No real WebSocket pairing exchange, real X25519 key generation, session-key derivation, or successful HarmonyOS 6.1 device-level Ed25519 verification has been completed yet.

## Codebase Understanding

### Architecture Overview

EggClip is a LAN-only clipboard sync tool. HarmonyOS is foreground-only and must not silently read the system clipboard. Pairing logic is intentionally layered:

- `PairingStore` owns UI-facing invitation state and keeps pairing secret material out of visible snapshots.
- `PairingHandshakeDraftService` converts a confirmed invitation and local public keys into protocol payloads/transcripts without exposing `pairingSecret`.
- `ProtocolFrameBuilderService` creates wire-level pre-auth handshake frames and round-trips them through `ProtocolParser`.
- `ProtocolHandshakeTransportSession` gates pre-auth handshake messages and replay/order behavior.
- `PairingClientHandshakeSessionService` orchestrates the in-memory client flow.
- `PairingAuthProofValidationService` validates and now optionally verifies AUTH_PROOF signatures.

Protocol runtime code is duplicated per platform: Rust desktop and ArkTS Harmony consume the same conceptual protocol/test vectors, but no shared runtime code is used.

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `AGENTS.md` | Project constraints and architecture rules | Must be read before continuing; contains product/security boundaries. |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony phase plan | Current work is in H3/H4/H5 pairing, crypto, and authenticated session preparation. |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop phase plan | Useful when aligning Harmony protocol work with desktop implementation. |
| `protocol/README.md` | Protocol v1 specification | Defines envelope, AUTH_PROOF transcript/hash/signature semantics, and encrypted frame rules. |
| `desktop/src-tauri/src/protocol/mod.rs` | Rust protocol reference | Contains canonical transcript/hash and tests that Harmony should mirror. |
| `desktop/src-tauri/src/crypto/mod.rs` | Rust crypto reference | Contains Ed25519, HKDF, AES-GCM, nonce and session key helpers. |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | ArkTS protocol model/parser/session gate | Central parser and canonical transcript implementation. |
| `harmony/entry/src/main/ets/services/transport/ProtocolFrameBuilderService.ets` | ArkTS pre-auth frame builder | Builds CLIENT_HELLO and AUTH_PROOF frames. |
| `harmony/entry/src/main/ets/services/pairing/PairingHandshakeDraftService.ets` | Client handshake draft builder | Validates invitation-derived server identity and creates client AUTH_PROOF transcript input. |
| `harmony/entry/src/main/ets/services/pairing/PairingClientHandshakeSessionService.ets` | In-memory client handshake orchestrator | Connects CLIENT_HELLO output, SERVER_HELLO input, and AUTH_PROOF output. |
| `harmony/entry/src/main/ets/services/pairing/PairingAuthProofValidationService.ets` | AUTH_PROOF validator/verifier boundary | Performs role/hash/signature shape checks and calls generic Ed25519 verification boundary. |
| `harmony/entry/src/main/ets/services/crypto/CryptoVectorService.ets` | Crypto vector validation and platform crypto experiments | Now exposes generic `verifyEd25519Signature(...)`. |
| `harmony/entry/src/main/ets/services/crypto/Sha256Service.ets` | Reusable SHA-256 helper | Used by invitation confirmation code and AUTH_PROOF transcriptHash. |
| `harmony/entry/src/test/LocalUnit.test.ets` | ArkTS regression tests | Contains all current protocol, pairing, storage, and crypto boundary tests. |

### Key Patterns Discovered

- Do not put business logic in pages/components. Use services and stores.
- For security-sensitive protocol additions, implement shape/hash/state validation first, then attach platform crypto.
- Do not log or persist pairing secrets, clipboard plaintext, raw keys, or full frames.
- Tests often allow platform crypto to fail explicitly in local unit runtime because DevEco unit tests may not reflect true device CryptoFramework/HUKS behavior.
- When adding protocol behavior, also update TODO and add ArkTS tests in `LocalUnit.test.ets`.
- The repository currently uses commits on `main`; no automatic branch creation/push unless the user asks.

## Work Completed

### Tasks Finished

- [x] Extracted generic Ed25519 verification entry point in Harmony crypto service.
- [x] Integrated Ed25519 verification boundary into AUTH_PROOF validation service.
- [x] Preserved pre-verification checks for AUTH_PROOF role, transcriptHash, canonical transcript, and 64-byte signature shape.
- [x] Added unit coverage for AUTH_PROOF verification boundary.
- [x] Updated Harmony TODO to document what is complete and what remains device-verified.
- [x] Ran Harmony validation commands successfully.

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `harmony/entry/src/main/ets/services/crypto/CryptoVectorService.ets` | Added `verifyEd25519Signature(publicKeyBase64Url, message, signatureBase64Url)` and made vector verification reuse it. Added public key/signature length checks. | Gives pairing/auth code a reusable crypto boundary instead of coupling to test-vector JSON. |
| `harmony/entry/src/main/ets/services/pairing/PairingAuthProofValidationService.ets` | Added `SIGNATURE_VERIFY_FAILED`, `cryptoError`, and `verifyPayloadSignatureAgainstTranscript(...)`. | Allows AUTH_PROOF receiver flow to validate transcript/hash/role and call Ed25519 verification through one service. |
| `harmony/entry/src/test/LocalUnit.test.ets` | Added AUTH_PROOF Ed25519 verification boundary test using shared fixture transcript/proof. | Locks the service contract while tolerating local DevEco runtime crypto limitations. |
| `HARMONY_DEVELOPMENT_TODO.md` | Recorded that generic Ed25519 verify entry and AUTH_PROOF verification boundary are done; true device confirmation remains open. | Keeps development plan honest and avoids over-claiming real-device verification. |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Expose generic `verifyEd25519Signature(...)` in `CryptoVectorService` instead of parsing auth proof in crypto code | Put verification directly in pairing service; keep only vector JSON method; create a new crypto service | Smallest change that reuses existing CryptoFramework import attempts and keeps protocol-specific logic in pairing. |
| Allow unit test to pass on either successful Ed25519 verification or explicit `SIGNATURE_VERIFY_FAILED` | Require success in local unit test; skip test; accept any failure | DevEco unit runtime may not reflect real HarmonyOS device crypto behavior. The contract now rejects hash/signature shape bugs while preserving true-device validation as TODO. |
| Do not mark “CryptoFramework/HUKS Ed25519 true verification” complete | Mark because code path exists; leave TODO open | Code path exists, but algorithm name/import format still needs HarmonyOS 6.1 real-device confirmation. |
| Keep AUTH_PROOF verification in a pairing-specific service | Put it in protocol parser/session gate | Parser should validate envelope/payload structure only; pairing service knows expected role, transcript, and remote identity. |

## Pending Work

### Immediate Next Steps

1. Decide whether to continue with Ed25519 true-device confirmation or move to X25519/HKDF session derivation boundary. The most direct next engineering step is X25519/HKDF shape/derivation service because real-device Ed25519 confirmation likely needs hardware/runtime testing.
2. Add Harmony X25519/HKDF service boundary mirroring Rust `desktop/src-tauri/src/crypto/mod.rs` and shared vectors under `protocol/test-vectors/crypto/`.
3. Extend `PairingClientHandshakeSessionService` to handle `AUTH_OK` and return a clear “authenticated pending session-key derivation” state, while still not writing trusted devices or keys.

### Blockers/Open Questions

- [ ] Need HarmonyOS 6.1 real-device validation for Ed25519 algorithm names, SPKI vs KeySpec public-key import, and one-shot verify behavior.
- [ ] Need true X25519/HKDF support confirmation in Harmony CryptoFramework/HUKS before marking real session derivation complete.
- [ ] Need design decision on where real local identity private key will live: HUKS alias lifecycle and signing API are not implemented.
- [ ] Need actual Desktop ↔ Harmony WebSocket pairing handshake integration after crypto/session derivation boundaries are stable.

### Deferred Items

- True HUKS Ed25519 signing/verification on device: deferred because current session focused on service boundaries and unit-testable behavior.
- Real X25519 ephemeral key generation and HKDF session keys: deferred to next crypto milestone.
- Trusted device persistence after pairing: deferred until handshake authentication and space key reception are real.
- Desktop-side pairing network integration: deferred until Harmony client handshake has actual crypto outputs.

## Context for Resuming Agent

### Important Context

Current branch `main` already contains recent commits through `1c172c1 feat: 提取通用Ed25519验证方法并集成到配对认证验证服务`. At the time this handoff was created, the only untracked file should be this handoff document. The key rule is not to claim cryptographic completion beyond what has been device-verified. Harmony now has an AUTH_PROOF verification boundary, but successful real Ed25519 verification on HarmonyOS 6.1 is still explicitly not proven. Continue to protect pairing secrets and clipboard content: no plaintext, raw keys, full invitation secrets, or full frames should be logged or persisted.

## Important Context

Current branch `main` already includes the Harmony AUTH_PROOF boundary work through commit `1c172c1`. The only expected working-tree change after this handoff is the new handoff file itself. Harmony has an AUTH_PROOF verification boundary and generic Ed25519 verify entry point, but HarmonyOS 6.1 real-device Ed25519 success is not confirmed; do not mark HUKS/CryptoFramework true verification complete until that is tested on device.

## Immediate Next Steps

1. Re-run `git status --short` and verify only this handoff file is untracked before starting new development.
2. Choose the next crypto milestone: either real-device Ed25519 verification or X25519/HKDF session derivation boundary.
3. If staying in local/unit-testable work, implement X25519/HKDF boundary next and keep true-device crypto TODOs open.

### Assumptions Made

- Local DevEco unit tests can compile and exercise CryptoFramework API shapes, but cannot be treated as final proof of real-device crypto behavior.
- Rust protocol implementation is the reference when ArkTS behavior is ambiguous.
- AUTH_PROOF signature verification should be performed over the canonical transcript string, not over the transcript hash.
- `pairingSecret` must not appear in client/server handshake frames, store snapshots, tests except fixed synthetic fixture assertions, or logs.

### Potential Gotchas

- `PairingInvitationPayload.issuerIdentityPublicKey` fixture value is `11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaapcHUro`; earlier hand-typed variants with `...IaaPcHURo` are different and will fail identity matching.
- `AUTH_PROOF_FIXTURE` uses a trusted-device context transcript from shared crypto vectors, while newer pairing invite tests use `pairing-invitation:v1:<invitationId>` context. Do not mix expected transcript hashes across these contexts.
- A 64-byte all-zero signature encodes to a long `AAAA...` string and can accidentally match the synthetic pairing secret substring in “no secret leakage” assertions. Use non-secret test signature constants when checking frame leakage.
- `git diff --stat` does not show untracked files, so check `git status --short` before assuming new services/handoff files are tracked.
- Handoff creation script may fail on Windows GBK decoding; set `PYTHONUTF8=1` and `PYTHONIOENCODING=utf-8` before running it.

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- DevEco hvigor wrapper:
  - `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`
- Java/SDK environment used for validation:
  - `JAVA_HOME`
  - `DEVECO_SDK_HOME`
  - `Path`
- Git on branch `main`
- Python for handoff scaffold/validation

### Active Processes

- None intentionally left running.

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`
- `PYTHONIOENCODING`

## Validation Performed

- `cd D:\Develop\eggclip\harmony`
- `$env:JAVA_HOME = 'C:\Program Files\Huawei\DevEco Studio\jbr'`
- `$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'`
- `$env:Path = "$env:JAVA_HOME\bin;$env:Path"`
- `& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' test --no-daemon`
- `& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon`

Both validation commands passed. Existing warnings remain around pasteboard permission, throwing functions, and missing signingConfig; these are existing project warnings, not new blockers from this session.

## Related Resources

- [AGENTS.md](../../AGENTS.md)
- [Harmony TODO](../../HARMONY_DEVELOPMENT_TODO.md)
- [Desktop TODO](../../DESKTOP_DEVELOPMENT_TODO.md)
- [Protocol README](../../protocol/README.md)
- [Previous handoff](./2026-07-04-205538-eggclip-pairing-invitation-validation.md)
- [CryptoVectorService.ets](../../harmony/entry/src/main/ets/services/crypto/CryptoVectorService.ets)
- [PairingAuthProofValidationService.ets](../../harmony/entry/src/main/ets/services/pairing/PairingAuthProofValidationService.ets)
- [LocalUnit.test.ets](../../harmony/entry/src/test/LocalUnit.test.ets)

---

**Security Reminder**: This handoff intentionally contains no real secrets, passwords, private keys, pairing invitation secrets, or clipboard plaintext.
