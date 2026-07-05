# Handoff: EggClip Harmony X25519 与 Ed25519 AUTH_PROOF 边界

## Session Metadata

- Created: 2026-07-05 15:35:17
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 约 4 个连续开发轮次

### Recent Commits (for context)

- 919e95c feat: 新增Ed25519签名服务并集成到配对握手流程
- 5067d6d feat: 新增PairingStore的buildPendingClientHandshakeMaterial方法，自动生成临时密钥对并构造CLIENT_HELLO草案
- 3973097 feat: 为配对握手添加基于临时私钥的共享密钥派生
- 69a5de5 feat: 新增X25519KeyAgreementService，封装CryptoFramework X25519临时密钥生成和共享秘密计算，并添加本地单元测试
- e11eb0f feat: 实现认证后远程历史元数据条件持久化

## Handoff Chain

- **Continues from**: [2026-07-05-111117-eggclip-pairing-context-server-hello.md](./2026-07-05-111117-eggclip-pairing-context-server-hello.md)
  - Previous title: EggClip pairingContext 与桌面 SERVER_HELLO 骨架
- **Supersedes**: None

## Current State Summary

本轮继续推进“扫码连接”主线，重点补齐 HarmonyOS 端正式握手的密码学服务边界。上一份 handoff 已完成 `pairingContext` 和桌面 SERVER_HELLO 骨架；本轮新增了 HarmonyOS 端 X25519 临时密钥生成与 shared secret 计算、PairingStore 自动生成临时 keypair 的握手材料、握手 session 从本机临时私钥和 SERVER_HELLO ephemeral public key 派生 session keys 的入口，以及 Ed25519 AUTH_PROOF 签名边界。当前仍未实现完整扫码连接：HUKS 持久 Ed25519 身份、服务端 AUTH_PROOF 真验签、真实 WebSocket 握手接线、AUTH_OK 后 trusted device/spaceKey 持久化还未完成。

## Codebase Understanding

### Architecture Overview

EggClip 是纯局域网剪贴板同步工具，扫码连接属于正式配对协议，不能复用未认证 POC 剪贴板通道。当前配对链路分层如下：

- `protocol/` 是共享协议事实来源，Rust 和 ArkTS 各自实现协议，不共享运行时代码。
- 桌面端已具备 invitation、SERVER_HELLO 骨架和认证后 transport 基础，主要在 `desktop/src-tauri/src/pairing/mod.rs`、`desktop/src-tauri/src/transport/mod.rs`、`desktop/src-tauri/src/protocol/mod.rs`。
- HarmonyOS 端 pairing 页面只负责导入邀请和用户确认；业务状态在 `harmony/entry/src/main/ets/store/PairingStore.ets`。
- HarmonyOS 端握手 draft、AUTH_PROOF、网络编排在 `harmony/entry/src/main/ets/services/pairing/`。
- HarmonyOS 端密码学边界在 `harmony/entry/src/main/ets/services/crypto/`。当前是 CryptoFramework 边界和测试向量边界，HUKS 持久密钥尚未接入。

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `harmony/entry/src/main/ets/services/crypto/X25519KeyAgreementService.ets` | CryptoFramework X25519 keypair/shared secret 边界 | 扫码配对临时共享秘密的基础 |
| `harmony/entry/src/main/ets/services/crypto/Ed25519SignatureService.ets` | CryptoFramework Ed25519 signing 边界 | 客户端 AUTH_PROOF 自动签名入口 |
| `harmony/entry/src/main/ets/store/PairingStore.ets` | 邀请解析、pending 配对材料生成 | 新增自动生成 X25519 临时 keypair，不把私钥写入 snapshot/draft |
| `harmony/entry/src/main/ets/services/pairing/PairingHandshakeDraftService.ets` | CLIENT_HELLO draft 与 auth transcript 构造 | `pairingContext`、本机/远端身份和 ephemeral key 都进入 canonical transcript |
| `harmony/entry/src/main/ets/services/pairing/PairingClientHandshakeSessionService.ets` | 客户端握手 session 状态机 | 新增真实 sharedSecret 派生入口和 Ed25519 AUTH_PROOF 签名入口 |
| `harmony/entry/src/main/ets/services/pairing/PairingClientNetworkHandshakeService.ets` | WebSocket 回调级握手编排 | 新增从内存 session 生成 AUTH_PROOF、AUTH_OK 后创建 authenticated transport 的入口 |
| `harmony/entry/src/test/LocalUnit.test.ets` | Harmony 本地单元测试 | 覆盖 X25519、Ed25519 signing、PairingStore 材料生成和握手 session |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony 开发计划 | 已同步当前完成项和剩余扫码连接待办 |
| `DESKTOP_DEVELOPMENT_TODO.md` | 桌面端开发计划 | 后续桌面端服务端验签/网络接线需要同步更新 |

### Key Patterns Discovered

- 私钥、pairingSecret、spaceKey 不能进入 UI snapshot、draft 序列化、普通日志、handoff 或测试快照。
- Harmony 单元环境对 CryptoFramework 算法支持可能与真机不同；测试允许 `platformCryptoFailed` 或签名格式不匹配类错误，但业务路径必须明确分类失败。
- `PairingHandshakeDraft` 只保存公开握手材料；X25519 临时私钥保存在 `PairingClientHandshakeSession` 或方法返回材料中。
- `PairingStore.buildPendingClientHandshakeMaterial` 是连接 UI/import 层与握手网络层的下一步入口：它返回 draft、公钥、临时私钥，但不把私钥暴露给 snapshot。
- `PairingClientHandshakeSessionService` 同时保留测试用入口和正式入口：旧入口允许调用方传入测试 signature/sharedSecret，新入口自动签名或自动派生 sharedSecret。

## Work Completed

### Tasks Finished

- [x] 新增 HarmonyOS X25519 key agreement 服务边界，支持生成临时 keypair 和基于 peer public key 派生 sharedSecret。
- [x] X25519 服务覆盖 base64url、32 字节长度校验、平台失败分类和 RFC/共享向量边界。
- [x] `PairingClientHandshakeSessionService` 支持保存本机临时私钥，记住 SERVER_HELLO，并在 AUTH_OK 前用真实 sharedSecret 派生 session keys。
- [x] `PairingClientNetworkHandshakeService` 增加从内存 ephemeral 私钥创建 authenticated transport session 的入口。
- [x] `PairingStore` 新增 `buildPendingClientHandshakeMaterial`，pending 邀请确认后自动生成 X25519 临时 keypair 并构造 CLIENT_HELLO draft。
- [x] 新增 HarmonyOS Ed25519 signing 服务边界，支持基于 32 字节私钥材料签名并输出 64 字节 base64url signature。
- [x] `PairingClientHandshakeSessionService` 增加 `acceptServerHelloAndSignAuthProof`，收到 SERVER_HELLO 后自动签名并生成 AUTH_PROOF。
- [x] `PairingClientNetworkHandshakeService` 增加 network 层 AUTH_PROOF 自动签名入口。
- [x] 为以上服务补充 Harmony 本地单元测试。
- [x] 更新 `HARMONY_DEVELOPMENT_TODO.md`，标记 X25519/Ed25519 边界完成，并保留 HUKS、真机确认、真实网络接线待办。

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `harmony/entry/src/main/ets/services/crypto/X25519KeyAgreementService.ets` | 新增 X25519 keypair/sharedSecret 服务 | 为扫码握手真实 sharedSecret 做平台边界 |
| `harmony/entry/src/main/ets/services/crypto/Ed25519SignatureService.ets` | 新增 Ed25519 signing 服务 | 为客户端 AUTH_PROOF 自动签名做平台边界 |
| `harmony/entry/src/main/ets/store/PairingStore.ets` | 新增 `PairingGeneratedHandshakeMaterialResult` 和 `buildPendingClientHandshakeMaterial` | 让配对入口可以自动生成临时 keypair，避免继续从 UI 传测试 public key |
| `harmony/entry/src/main/ets/services/pairing/PairingClientHandshakeSessionService.ets` | 保存本机临时私钥、SERVER_HELLO；新增 sharedSecret 派生入口和 Ed25519 signing 入口 | 让客户端握手 session 可以从真实材料推进到 AUTH_PROOF/AUTH_OK |
| `harmony/entry/src/main/ets/services/pairing/PairingClientNetworkHandshakeService.ets` | 新增 network 层自动签名和 ephemeral sharedSecret 入口 | 后续 WebSocket 收包回调可直接使用，不再传测试 signature/sharedSecret |
| `harmony/entry/src/test/LocalUnit.test.ets` | 增加 X25519、Ed25519 signing、PairingStore、握手 session/network 测试 | 防止后续回归泄露私钥或退回测试材料 |
| `HARMONY_DEVELOPMENT_TODO.md` | 同步完成/待办状态 | 让计划文档反映真实扫码连接进度 |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| X25519 临时私钥不进入 `PairingHandshakeDraft` | 放入 draft；放入 store snapshot；只保存在 session/返回材料 | draft/snapshot 容易被 UI、日志或测试序列化；私钥只应短期存在于内存握手路径 |
| Ed25519 signing 先做 CryptoFramework 私钥材料边界，HUKS 后接 | 先直接做 HUKS；先用测试签名继续推进；新增 CryptoFramework service | HUKS API 和真机行为还需确认；先建立签名边界能让握手服务摆脱测试签名 |
| 单元测试允许平台失败分类 | 强制要求本地单元环境跑通所有算法；完全跳过算法测试 | DevEco 本地单元环境可能与真机 CryptoFramework 能力不同；明确失败分类比误判业务失败更可靠 |
| 保留旧测试入口 | 删除传入 signature/sharedSecret 的旧方法；保留过渡方法 | 现有测试向量和服务单测仍需要固定输入，保留可降低迁移风险 |

## Pending Work

## Immediate Next Steps

1. 接入 HarmonyOS 本机 Ed25519 身份来源：生成/读取本机 `deviceId`、identity public key 和 HUKS/等效私钥引用，替换当前 `localIdentityPrivateSeed` 字符串入参。
2. 把 `PairingPage` / 设备页配对入口接到 `PairingStore.buildPendingClientHandshakeMaterial` 和 `PairingClientNetworkHandshakeService.start`，开始真实发送 CLIENT_HELLO。
3. 在 Harmony WebSocket pairing handshake 收包路径中串联：SERVER_HELLO -> `acceptServerHelloAndSignAuthProof` -> 发送 AUTH_PROOF -> AUTH_OK -> `acceptAuthOkAndCreateTransportSessionFromEphemeral`。
4. 桌面端接入服务端 AUTH_PROOF 真验签和 AUTH_OK 返回，不能只依赖公开 `pairingContext`。
5. 成功配对后持久化 trusted device、space/member 信息并安全接收/保存 spaceKey。

### Blockers/Open Questions

- [ ] HUKS Ed25519 私钥生成、导出 public key、签名的准确 API 形态还未真机验证。
- [ ] HarmonyOS 6.1 真机上 Ed25519/X25519 KeySpec 字节序、算法名和 one-shot signing/verify 行为仍需确认。
- [ ] 当前客户端 AUTH_PROOF signing service 接受 32 字节私钥材料；正式实现必须替换为 HUKS 私钥引用或系统安全存储路径。
- [ ] 桌面端服务端 AUTH_PROOF 真验签和 invitation 消费时机仍未完成；CLIENT_HELLO/SERVER_HELLO 不是安全完成点。
- [ ] pairingSecret 参与正式配对证明的完整设计/实现仍未落地。

### Deferred Items

- 真机联调：必须等 HUKS/真实网络接线后执行，模拟器结果不能替代。
- trusted device 管理 UI：依赖成功配对持久化后再做。
- spaceKey 安全下发和轮换：需要在 AUTH_OK/后续加密消息设计稳定后接入。
- 首页/设备页成功配对体验 polish：等真实配对状态流可用后再完善。

## Context for Resuming Agent

## Important Context

当前仓库 `main` 已包含最近 4 个关键提交：X25519 服务、PairingStore 自动临时 keypair、握手 session sharedSecret 派生、Ed25519 signing/AUTH_PROOF 入口。生成本 handoff 时工作区只有本 handoff 文件未跟踪。代码层已非常接近“扫码后发起正式握手”，但还不能对用户宣称能扫码连接；缺口在 HUKS 本机身份、真实 WebSocket 接线、桌面端 AUTH_PROOF 验签、AUTH_OK 和 trusted device/spaceKey 持久化。

不要把 `Ed25519SignatureService.signMessage(privateSeed, message)` 当最终安全实现。它是 CryptoFramework signing 边界和过渡入口，正式路径必须让私钥留在 HUKS/系统安全存储中。不要在聊天、日志或文档中复制测试向量里的私钥材料；本 handoff 也刻意未写入具体 private seed。

### Assumptions Made

- HarmonyOS 本地单元测试环境可能不完整支持 Ed25519/X25519，因此测试接受明确的平台失败分类。
- `pairingContext` 只是公开路由上下文，不是认证依据。
- CLIENT_HELLO/SERVER_HELLO 完成后仍未认证；只有 AUTH_PROOF 验签、sharedSecret/session keys、AUTH_OK 全部通过后才能进入 trusted/authenticated。
- 临时 X25519 私钥只需在一次握手内存中保存，不应落库。

### Potential Gotchas

- 不要把 `PairingStoreSnapshot` 当作安全材料载体；它面向 UI，不能带私钥或 pairingSecret。
- `PairingGeneratedHandshakeMaterialResult` 会返回临时私钥，调用方必须只传给握手网络服务，不要存入状态展示或日志。
- `acceptServerHelloAndBuildAuthProof` 是旧的测试/过渡入口；真实路径应优先使用 `acceptServerHelloAndSignAuthProof`。
- `acceptAuthOkAndCreateTransportSession` 允许外部传 sharedSecret；真实路径应优先使用 `acceptAuthOkAndCreateTransportSessionFromEphemeral`。
- Harmony 编译会出现既有 ArkTS warning，例如 RDB throw warning、Pasteboard 权限 warning、No signingConfig；本轮未解决这些 warning。
- Windows PowerShell 下运行 handoff 脚本前设置 `$env:PYTHONUTF8='1'`，避免 GBK 解码问题。

## Environment State

### Tools/Services Used

- PowerShell, working directory `D:\Develop\eggclip`
- DevEco hvigor wrapper: `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`
- Java runtime: `C:\Program Files\Huawei\DevEco Studio\jbr`
- DevEco SDK: `C:\Program Files\Huawei\DevEco Studio\sdk`
- Session handoff skill scripts: `C:\Users\caozhipeng\.agents\skills\session-handoff\scripts`

### Active Processes

- No long-running dev server, Tauri process, watcher, or emulator process was intentionally left running by this session.

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Verification Performed

- `cd D:\Develop\eggclip\harmony; hvigorw.bat test --no-daemon` passed after X25519/Ed25519 changes.
- `cd D:\Develop\eggclip\harmony; hvigorw.bat assembleHap --no-daemon` passed after X25519/Ed25519 changes.
- `git diff --check` passed; only LF/CRLF warnings were reported.
- No desktop Rust verification was rerun in this handoff turn because the recent work was Harmony-only and already committed.

## Related Resources

- [AGENTS.md](../../AGENTS.md)
- [docs/EggClip最佳实现方案.md](../../docs/EggClip最佳实现方案.md)
- [HARMONY_DEVELOPMENT_TODO.md](../../HARMONY_DEVELOPMENT_TODO.md)
- [DESKTOP_DEVELOPMENT_TODO.md](../../DESKTOP_DEVELOPMENT_TODO.md)
- [protocol/README.md](../../protocol/README.md)
- [harmony/entry/src/main/ets/services/crypto/X25519KeyAgreementService.ets](../../harmony/entry/src/main/ets/services/crypto/X25519KeyAgreementService.ets)
- [harmony/entry/src/main/ets/services/crypto/Ed25519SignatureService.ets](../../harmony/entry/src/main/ets/services/crypto/Ed25519SignatureService.ets)
- [harmony/entry/src/main/ets/store/PairingStore.ets](../../harmony/entry/src/main/ets/store/PairingStore.ets)
- [harmony/entry/src/main/ets/services/pairing/PairingClientHandshakeSessionService.ets](../../harmony/entry/src/main/ets/services/pairing/PairingClientHandshakeSessionService.ets)
- [harmony/entry/src/main/ets/services/pairing/PairingClientNetworkHandshakeService.ets](../../harmony/entry/src/main/ets/services/pairing/PairingClientNetworkHandshakeService.ets)
- [harmony/entry/src/test/LocalUnit.test.ets](../../harmony/entry/src/test/LocalUnit.test.ets)

---

Security note: this handoff intentionally avoids full invitation strings, pairingSecret, private keys, spaceKey, clipboard text samples, and full protocol frames.
