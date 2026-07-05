# Handoff: EggClip pairingContext 与桌面 SERVER_HELLO 骨架

## Session Metadata

- Created: 2026-07-05 11:11:17
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 约 1 个开发轮次

### Recent Commits (for context)

- 5f03e31 feat: 新增配对握手pairingContext字段及服务端接受CLIENT_HELLO骨架
- 03ad6da feat: 添加配对握手连接入口和明文握手帧处理
- 6c382f6 feat: 新增客户端配对网络握手编排器及单元测试
- 709185e feat: 在配对客户端握手会话中接入AUTH_OK完成步骤，派生会话密钥并创建认证传输会话
- 6c2cee7 feat: ProtocolTransportSession 接入 AES-GCM 解密与 AAD 校验

## Handoff Chain

- **Continues from**: [2026-07-04-224336-eggclip-auth-proof-verification-boundary.md](./2026-07-04-224336-eggclip-auth-proof-verification-boundary.md)
  - Previous title: EggClip Harmony AUTH_PROOF verification boundary
- **Supersedes**: None

## Current State Summary

本轮围绕“扫码后真正进入配对握手”的主链路推进。之前鸿蒙端已经能扫码/粘贴邀请、生成 CLIENT_HELLO draft，并有客户端握手编排服务；但 CLIENT_HELLO 没有携带可让桌面端定位 invitation 的公开上下文。现在协议层新增了可选 `pairingContext` 字段，鸿蒙扫码配对的 CLIENT_HELLO 会携带 `pairing-invitation:v1:<invitationId>`，桌面端新增了 `accept_pairing_client_hello` 业务骨架，可以根据该公开上下文定位 active invitation，校验空间和发行设备后生成 SERVER_HELLO。当前仍未接入真实 WebSocket server 收包路径，也没有完成 pairingSecret 证明、真实 X25519/Ed25519、AUTH_OK 和 trusted device 持久化。

## Codebase Understanding

### Architecture Overview

EggClip 是纯局域网剪贴板同步工具，v1 固定为 Windows 桌面端和 HarmonyOS 前台客户端。扫码连接属于配对与安全握手链路，不能退化成未认证 POC 连接。当前架构分层如下：

- `protocol/` 是共享协议事实来源，Rust 和 ArkTS 各自实现，不共享运行时代码。
- 桌面端协议类型和加密边界在 `desktop/src-tauri/src/protocol/mod.rs`、`desktop/src-tauri/src/transport/session.rs`。
- 桌面端邀请、空间、配对业务在 `desktop/src-tauri/src/pairing/mod.rs`，邀请 registry 存在 SQLite，但 pairingSecret 原文不落库。
- 鸿蒙端协议模型在 `harmony/entry/src/main/ets/models/ProtocolModels.ets`。
- 鸿蒙端扫码邀请和客户端握手 draft 在 `harmony/entry/src/main/ets/services/pairing/`。
- 鸿蒙端 WebSocket 有 POC、正式协议、配对握手三类入口，位于 `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets`。

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `protocol/README.md` | 协议说明 | 记录 `pairingContext` 是公开路由和 transcript 绑定字段，不含 pairingSecret |
| `protocol/v1.schema.json` | v1 envelope/schema | `helloPayload` 允许可选 `pairingContext` |
| `protocol/test-vectors/handshake/client-hello.valid.json` | 共享 CLIENT_HELLO 测试向量 | 已包含 `pairingContext`，Rust/ArkTS 消费 |
| `desktop/src-tauri/src/protocol/mod.rs` | Rust 协议模型、解析和序列化 | 新增 `serialize_pre_auth_envelope`，HelloPayload 支持 `pairing_context` |
| `desktop/src-tauri/src/pairing/mod.rs` | 桌面端空间、邀请、配对业务 | 新增 `accept_pairing_client_hello` 和 SERVER_HELLO 骨架 |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | ArkTS 协议模型和 parser | HelloPayload 支持可选 `pairingContext` |
| `harmony/entry/src/main/ets/services/pairing/PairingHandshakeDraftService.ets` | 鸿蒙端 CLIENT_HELLO draft | 扫码邀请生成的 CLIENT_HELLO payload 会携带公开 `pairingContext` |
| `harmony/entry/src/test/LocalUnit.test.ets` | Harmony 本地单测 | 覆盖 CLIENT_HELLO frame 中的 `pairingContext` |
| `DESKTOP_DEVELOPMENT_TODO.md` | 桌面端开发计划 | 已记录桌面端 SERVER_HELLO 骨架完成项 |
| `HARMONY_DEVELOPMENT_TODO.md` | 鸿蒙端开发计划 | 已记录鸿蒙 CLIENT_HELLO 携带公开 `pairingContext` |

### Key Patterns Discovered

- 协议变更必须同步 schema、README、共享 test vector、Rust 类型、ArkTS 类型和两端测试。
- `pairingContext` 是公开值，格式为 `pairing-invitation:v1:<invitationId>`；它只用于定位 invitation 和绑定 transcript，不能包含 pairingSecret。
- 桌面端 `accept_pairing_client_hello` 只做 CLIENT_HELLO 的结构和 invitation 状态校验，并生成 SERVER_HELLO；不能在这个阶段消费 invitation。
- invitation 的一次性消费应等到后续 pairingSecret 证明和 AUTH_PROOF 验证完成后再执行。
- 鸿蒙端不能静默读剪贴板；邀请导入必须通过扫码或真实 PasteButton 授权路径。
- 日志、诊断、handoff 都不能写入剪贴板正文、pairingSecret、私钥、spaceKey、完整网络帧或真实敏感样本。

## Work Completed

### Tasks Finished

- [x] 在共享协议中为 HelloPayload 增加可选 `pairingContext`。
- [x] 更新 `protocol/README.md`，明确 `pairingContext` 公开、非 secret、邀请配对必需。
- [x] 更新 `protocol/v1.schema.json` 和 `client-hello.valid.json`。
- [x] Rust `HelloPayload` 增加 `pairing_context: Option<String>` 并校验 transcript field。
- [x] Rust 新增 `serialize_pre_auth_envelope`，用于 SERVER_HELLO/AUTH_OK 等明文握手帧序列化。
- [x] 桌面端新增 `PairingServerHelloDraft` 和 `accept_pairing_client_hello`。
- [x] 桌面端测试覆盖：CLIENT_HELLO 成功生成 SERVER_HELLO、缺失 pairingContext 被拒绝、邀请不会提前消费。
- [x] ArkTS `HelloPayload` 增加可选 `pairingContext` 并在 parser 中校验。
- [x] Harmony `PairingHandshakeDraftService` 生成 CLIENT_HELLO payload 时携带公开 `pairingContext`。
- [x] Harmony 单测断言 CLIENT_HELLO frame 中包含 `pairingContext`，且不包含 pairingSecret。
- [x] 更新桌面端和 Harmony 端 TODO 文档。

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `protocol/README.md` | 添加 `pairingContext` 示例和语义说明 | 防止后续误把它当 secret 或省略 |
| `protocol/v1.schema.json` | `helloPayload` 增加可选 `pairingContext` | 让共享协议 schema 覆盖扫码配对路由上下文 |
| `protocol/test-vectors/handshake/client-hello.valid.json` | 增加 `pairingContext` 字段 | 让两端测试向量同步新协议字段 |
| `desktop/src-tauri/src/protocol/mod.rs` | 新增 pre-auth 序列化；HelloPayload 增加可选 pairing_context | 桌面端后续需要发 SERVER_HELLO/AUTH_OK |
| `desktop/src-tauri/src/pairing/mod.rs` | 新增 CLIENT_HELLO 接收和 SERVER_HELLO 骨架 | 为桌面端真实 WebSocket 握手入口做业务层准备 |
| `harmony/entry/src/main/ets/models/ProtocolModels.ets` | HelloPayload/parser 支持可选 `pairingContext` | 让 ArkTS 可解析/构造新字段 |
| `harmony/entry/src/main/ets/services/pairing/PairingHandshakeDraftService.ets` | CLIENT_HELLO payload 写入 `pairingContext` | 桌面端才能路由到对应 invitation |
| `harmony/entry/src/test/LocalUnit.test.ets` | 增加 CLIENT_HELLO frame 字段断言 | 防止后续回归丢失 `pairingContext` |
| `DESKTOP_DEVELOPMENT_TODO.md` | 记录 Rust HelloPayload 和 SERVER_HELLO 骨架完成项 | 保持计划文档与实际进度一致 |
| `HARMONY_DEVELOPMENT_TODO.md` | 记录 CLIENT_HELLO 携带公开 `pairingContext` | 保持计划文档与实际进度一致 |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| `pairingContext` 放入 HelloPayload，且可选 | 放入 envelope 顶层；放入 AUTH_PROOF；保持只在本地 draft | 桌面端必须在收到 CLIENT_HELLO 时就能定位 invitation；放入 HelloPayload 影响面小，且可选以兼容 trusted-device reconnect |
| `pairingContext` 不包含 pairingSecret | 直接携带 pairingSecret；携带 invitationId；携带 `pairing-invitation:v1:<id>` | pairingSecret 是高熵 secret，不能进网络明文；版本化上下文可绑定 transcript 并支持后续扩展 |
| 桌面端 CLIENT_HELLO 骨架不消费 invitation | 收到 CLIENT_HELLO 立即 mark consumed；等 AUTH_PROOF 后消费 | CLIENT_HELLO 只证明“知道 invitationId”，不证明知道 pairingSecret 或拥有设备私钥；提前消费会导致 DoS 和错误配对 |
| 先补业务层函数，不直接接 WebSocket server | 直接改 POC WebSocket server；先补可测业务函数 | 业务层可单测，避免把正式配对逻辑和 POC 明文剪贴板路径混在一起 |

## Pending Work

## Immediate Next Steps

1. 桌面端把 `accept_pairing_client_hello` 接入真实 WebSocket server 的配对握手路径：收到 CLIENT_HELLO 后调用该函数，并把 `server_hello_frame` 发回鸿蒙端。
2. 为桌面端配对握手建立 session 状态对象，保存 invitationId、peer device/public key、双方 ephemeral public key、pairingContext，供后续 AUTH_PROOF 验证和 AUTH_OK 使用。
3. 接入真实 X25519 临时密钥生成：桌面端生成 server ephemeral key pair；鸿蒙端生成 client ephemeral key pair；双方用 sharedSecret 驱动 session key 派生。
4. 设计并实现 pairingSecret 参与证明的方式，避免只凭公开 `pairingContext` 就能推进配对。
5. 完成 AUTH_PROOF 真签名/验签、AUTH_OK、邀请消费、trusted device 持久化。

### Blockers/Open Questions

- [ ] pairingSecret 如何参与正式配对通道证明尚未落地。当前实现只把 invitationId 作为公开路由上下文。
- [ ] HarmonyOS CryptoFramework/HUKS 的 Ed25519/X25519 真机算法名、公钥导入格式和 one-shot 行为仍需真机确认。
- [ ] 桌面端正式配对 WebSocket server path 还没和 POC WebSocket path 分离完成。
- [ ] 配对成功后 spaceKey 和成员信息如何安全下发、如何落库还未完成。

### Deferred Items

- 真正消费 invitation：必须等 pairingSecret 证明和 AUTH_PROOF 验证完成后再做。
- trusted device 持久化：必须等身份、公钥、空间绑定都验证完成后再写入。
- 自动连接已配对设备：依赖 trusted device 列表和正式 authenticated session。
- UI 成功/失败态 polish：等功能链路接通后再做。

## Context for Resuming Agent

## Important Context

当前主线是“扫码连接”。扫码导入和确认码 UI 已有，最新提交让鸿蒙 CLIENT_HELLO 能携带公开 `pairingContext`，桌面端能根据它找到对应 active invitation 并生成 SERVER_HELLO。这个阶段不是完整安全配对：没有证明 pairingSecret，没有真实 X25519 shared secret，没有真实 Ed25519 AUTH_PROOF 验签，也没有 AUTH_OK 后 trusted device 持久化。下一位 agent 不要把 `accept_pairing_client_hello` 当成安全完成点；它只是服务端握手入口骨架。

当前工作树在生成 handoff 前代码已提交到 `main`，最近提交是 `5f03e31`。生成 handoff 后仅 handoff 文件本身未跟踪。

### Assumptions Made

- `pairingContext` 可以作为公开路由上下文传输，因为它只包含 invitationId，不包含 pairingSecret。
- 邀请配对的 CLIENT_HELLO 必须带 `pairingContext`；已配对设备重连可以不带或使用后续 trusted-device context。
- 桌面端发 SERVER_HELLO 时回显同一个 `pairingContext`，以便双方 transcript 绑定同一上下文。
- invitation 不应在 CLIENT_HELLO 阶段消费。

### Potential Gotchas

- `pairingContext` 是公开值，不是认证。不能用它替代 pairingSecret 或 AUTH_PROOF。
- 不能把完整邀请字符串、pairingSecret、spaceKey、私钥、剪贴板正文写入日志、handoff 或测试快照。
- 桌面端 `accept_pairing_client_hello` 当前使用传入的 `server_ephemeral_public_key`，还没有生成真实 X25519 key pair。
- `serialize_pre_auth_envelope` 现在是 Rust 协议层通用能力，后续 AUTH_OK 也应复用它，不要手拼 JSON。
- Harmony `PairingHandshakeDraftService` 的 draft 序列化测试会检查不泄露 pairingSecret；新增字段时注意不要把 invitation payload 整体塞进网络帧。
- `cargo fmt -- --check` 会格式化 Rust 测试中的长 assert；如果失败先跑 `cargo fmt`。
- Windows 下 handoff 脚本可能遇到 GBK 解码问题；使用 `$env:PYTHONUTF8='1'` 后重跑。

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Rust/Cargo under `desktop/src-tauri`
- Node.js for `protocol/scripts/validate-fixtures.mjs`
- DevEco hvigor wrapper for Harmony build/test
- Session handoff skill scripts under `C:\Users\caozhipeng\.agents\skills\session-handoff\scripts`

### Active Processes

- No long-running app/dev server intentionally left running.
- Verification commands completed normally.

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Verification Performed

- `cargo test` in `D:\Develop\eggclip\desktop\src-tauri`: passed, 109 tests.
- `cargo check` in `D:\Develop\eggclip\desktop\src-tauri`: passed.
- `cargo fmt -- --check` in `D:\Develop\eggclip\desktop\src-tauri`: passed after formatting.
- `node protocol/scripts/validate-fixtures.mjs`: passed.
- `hvigorw.bat test --no-daemon` in `D:\Develop\eggclip\harmony`: passed.
- `hvigorw.bat assembleHap --no-daemon` in `D:\Develop\eggclip\harmony`: passed, existing ArkTS warnings only.
- `git diff --check`: passed, only LF/CRLF warnings.

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`
- `protocol/v1.schema.json`
- `protocol/test-vectors/handshake/client-hello.valid.json`
- `desktop/src-tauri/src/pairing/mod.rs`
- `desktop/src-tauri/src/protocol/mod.rs`
- `harmony/entry/src/main/ets/services/pairing/PairingHandshakeDraftService.ets`
- `harmony/entry/src/main/ets/models/ProtocolModels.ets`

---

Security note: this handoff intentionally avoids full invitation strings, pairingSecret, private keys, spaceKey, clipboard text samples, and full protocol frames.
