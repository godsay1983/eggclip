# Handoff: EggClip 配对后加密下发空间密钥

## Session Metadata
- Created: 2026-07-05 20:08:08
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 约 1 个开发回合

### Recent Commits (for context)
  - f8d4a05 feat: 新增配对完成后加密下发空间密钥及鸿蒙端接收处理
  - 708bcce feat: 配对完成后持久化可信设备
  - 8bb8383 feat: 增强配对错误处理和用户提示，修复设备ID生成和数据库迁移
  - cf68181 refactor: 重构配对页面状态管理，分离输入框与内部状态
  - 853d3ed feat: 接入真实WebSocket配对握手，添加配对连接UI和测试

## Handoff Chain

- **Continues from**: [2026-07-05-153517-eggclip-harmony-x25519-ed25519-auth-proof.md](./2026-07-05-153517-eggclip-harmony-x25519-ed25519-auth-proof.md)
  - Previous title: EggClip Harmony X25519 与 Ed25519 AUTH_PROOF 边界
- **Supersedes**: None

## Current State Summary

本阶段已经把“扫码/粘贴邀请 -> 人工确认码 -> 输入桌面端 IP/端口 -> CLIENT_HELLO/AUTH_PROOF -> AUTH_OK”之后的关键一步接上：桌面端在 AUTH_OK 后通过同一认证会话发送加密 `SPACE_KEY_ROTATED`，Harmony 端在同一 WebSocket 上切换到认证协议 session，解密并校验该帧，然后用一个 RDB transaction 同时保存同步空间 key 引用占位和桌面端 trusted device。当前工作区干净，最近提交为 `f8d4a05`。还没有完成真实 HUKS import，也还没有进入正式剪贴板同步生命周期。

## Codebase Understanding

### Architecture Overview

- 桌面端仍使用现有 POC WebSocket 入口承载正式握手帧；`desktop/src-tauri/src/transport/mod.rs` 负责握手帧路由和临时 authenticated session 接管。
- Rust 协议层已有 `SPACE_KEY_ROTATED` message type；本阶段明确其在邀请配对后的语义：初始同步空间 key 只能放在认证后 AEAD 密文帧中下发。
- Harmony 端 `WebSocketTransportService` 原本只把该连接当作 handshake session 解码；现在通过 `protocolSessionProvider` 在 `AUTH_OK` 后转入 `ProtocolTransportSession` 解码认证业务帧。
- Harmony 端 `PairingConnectionStore` 是配对连接编排中心。它现在不会在 AUTH_OK 时提前落库，而是等到 `SPACE_KEY_ROTATED` 解密、字段校验和 key 长度校验成功后再落库。
- Harmony 端新增 `PairingRdbRepository.persistCompletion`，用 `RdbCommandRunner.executeTransaction` 把 space 和 device 写入绑定为一个事务，避免配对失败留下半完成 trusted device。

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/src-tauri/src/transport/mod.rs` | 桌面 WebSocket、握手路由和 authenticated session 接管 | `AUTH_OK` 后构造并发送加密 `SPACE_KEY_ROTATED`；发送后桌面出站计数器从下一个值继续 |
| `desktop/src-tauri/src/protocol/mod.rs` | Rust v1 protocol parser/types/tests | 新增 encrypted `SPACE_KEY_ROTATED` fixture 消费测试 |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | Harmony WebSocket 收发和帧解码边界 | `AUTH_OK` 后同一 socket 改用 authenticated protocol session 解密业务帧 |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Harmony 配对连接状态机和落库编排 | 处理 `AUTH_OK`、`SPACE_KEY_ROTATED`，校验 payload，并触发配对完成事务 |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | Harmony RDB repository facade | 新增 `PairingRdbRepository` 事务保存同步空间和可信设备 |
| `protocol/README.md` | 协议语义说明 | 新增 Space Key Delivery 规则 |
| `protocol/test-vectors/sync/encrypted-space-key-rotated-envelope.valid.json` | 共享协议向量 | 明确 `SPACE_KEY_ROTATED` 是认证后 encrypted envelope |
| `DESKTOP_DEVELOPMENT_TODO.md` | 桌面阶段计划 | 已标记加密下发和出站计数器衔接进展 |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony 阶段计划 | 已标记加密接收、事务保存和剩余 HUKS import 工作 |

### Key Patterns Discovered

- 不要在 `AUTH_OK` 时就持久化 Harmony trusted device。`SPACE_KEY_ROTATED` 接收或保存失败时，不能留下半完成配对记录。
- Harmony 端当前只能生成并校验 `huks://` alias/引用；真实 key import 仍未实现。任何 UI 或 TODO 都必须写清这是占位，不是完整安全存储。
- 桌面端发送 `SPACE_KEY_ROTATED` 时使用握手派生的 `server_to_client` session key 和认证业务帧路径，不应走明文 handshake envelope。
- 配对链路中的邀请 secret、space key、剪贴板正文都不能写入日志、文档、测试快照或 UI 可复制区域。
- 修改协议语义时同步更新 README、测试向量、Rust/ArkTS 消费边界和 TODO，避免只有实现没有协议记录。

## Work Completed

### Tasks Finished

- [x] 桌面端 AUTH_PROOF 成功后回 `AUTH_OK` 并发送加密 `SPACE_KEY_ROTATED`。
- [x] 桌面端通过 Windows Credential Manager 边界加载本地 space key，并只把 key 放入 AEAD 密文 payload。
- [x] 桌面端发送初始 `SPACE_KEY_ROTATED` 后把 authenticated session 出站计数器推进到下一个安全值，避免 nonce 重用。
- [x] Harmony 端同一 WebSocket 在 `AUTH_OK` 后切换到 authenticated protocol decoder。
- [x] Harmony 端解密 `SPACE_KEY_ROTATED`，校验 `spaceId`、`keyVersion`、`delivery` 和 32 字节 key 长度。
- [x] Harmony 端明文 key 字节校验后立即清零，并只把 `huks://` alias 写入 RDB。
- [x] Harmony 端用 RDB transaction 同时保存同步空间 key 引用和桌面端 trusted device。
- [x] 新增 encrypted `SPACE_KEY_ROTATED` 共享 envelope 测试向量，并接入 Rust 协议测试。
- [x] 更新协议 README、桌面 TODO 和 Harmony TODO。

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src-tauri/src/transport/mod.rs` | AUTH_PROOF route 支持返回多帧；新增 space key delivery frame 构造；AUTH_OK 后发送 encrypted `SPACE_KEY_ROTATED` | 让桌面端在配对成功后把初始同步空间 key 通过认证会话发给 Harmony |
| `desktop/src-tauri/src/protocol/mod.rs` | 新增 encrypted `SPACE_KEY_ROTATED` fixture parser test | 防止协议类型回退为明文或未被 parser 覆盖 |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | 增加 `protocolSessionProvider`，认证后用 `ProtocolTransportSession` 解码 | 支持同一 socket 从握手帧切到加密业务帧 |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | AUTH_OK 只创建内存 session；收到 `SPACE_KEY_ROTATED` 后校验并触发配对完成保存 | 避免半完成 trusted device；接上加密空间 key 接收路径 |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | 新增 `PairingRdbRepository.persistCompletion` transaction facade | 同步空间和设备信任必须一起写入或一起回滚 |
| `protocol/README.md` | 新增 Space Key Delivery 章节 | 固化邀请配对后初始 space key 下发语义和安全规则 |
| `protocol/test-vectors/README.md` | 说明 sync 目录包含 encrypted business envelope fixtures | 让测试向量目录语义与新增 fixture 一致 |
| `protocol/test-vectors/sync/encrypted-space-key-rotated-envelope.valid.json` | 新增 encrypted `SPACE_KEY_ROTATED` envelope fixture | 共享协议验证材料 |
| `DESKTOP_DEVELOPMENT_TODO.md` | 标记 encrypted space key delivery 和 counter 衔接进展 | 反映桌面端当前阶段完成度 |
| `HARMONY_DEVELOPMENT_TODO.md` | 标记 authenticated 接收、事务保存和剩余 HUKS import | 反映 Harmony 端当前阶段完成度和未完成边界 |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| 使用已有 `SPACE_KEY_ROTATED` 类型承载初始 space key 下发 | 新增 `SPACE_KEY_DELIVERY` 类型；复用 `SPACE_KEY_ROTATED`；继续暂不下发 | 该类型已在协议枚举中存在，语义上可表达 key version 更新/初始下发；复用减少协议面扩张 |
| `AUTH_OK` 后立刻发送 encrypted business frame | 把 key 放进 `AUTH_OK` payload；另开连接；同一连接发认证业务帧 | `AUTH_OK` 是明文握手完成信号，不能携带 key；同一认证会话能复用已派生的双向 session key |
| Harmony 不在 `AUTH_OK` 时提前落库 trusted device | AUTH_OK 即落库；收到 key 后再落库；失败后补清理 | 收到 key 前配对不完整。等待 `SPACE_KEY_ROTATED` 后一次性保存，最符合“配对失败不遗留半完成 device” |
| Harmony 当前只保存 HUKS alias 占位，不假装完成真实 HUKS import | 直接把 key 写 RDB；先 alias 占位；立刻接 HUKS import | RDB 明文保存违反安全约束；真实 HUKS import 还需要真机 API 验证，因此先把边界和事务链路接稳 |
| 增加 shared encrypted envelope fixture | 只更新 README；只加 Rust 单测；加共享 fixture 并由 Rust 消费 | 协议语义变动应有共享测试向量，避免跨端理解漂移 |

## Pending Work

## Immediate Next Steps

1. 在 HarmonyOS 真机上重新跑完整配对：桌面端生成邀请，手机扫码/粘贴，确认码一致，输入桌面 IP/端口，点击连接并发送握手，确认 Harmony 状态从“配对握手已认证”继续到“配对已保存”。
2. 接入 Harmony 端真实 HUKS import/generate 流程：将解密出的 32 字节 `spaceKey` 导入或包装到 HUKS/等效安全存储，并只保留 alias；失败时不能落库 trusted device。
3. 将完成配对后的 trusted device/space key 引用接入正式连接管理和剪贴板同步 lifecycle，而不是停在配对页面状态。
4. 补充 Harmony 端针对 `SPACE_KEY_ROTATED` 的本地单测，覆盖字段不匹配、key 长度错误、未认证帧、RDB transaction 失败等路径。
5. 继续推进服务端 AUTH_PROOF 真实 Ed25519 验签和 pairingSecret 参与正式配对通道派生/证明的 TODO。

### Blockers/Open Questions

- [ ] Harmony HUKS 对 32 字节对称 key import/generate/alias 管理的具体 API 和限制仍需真机确认。
- [ ] 当前桌面端仍通过 POC WebSocket server 承载正式配对帧；正式 ConnectionManager/session lifecycle 尚未接管。
- [ ] 配对完成后的空间成员信息目前只有桌面端 trusted device 和 key version，完整成员列表/轮换流程未实现。
- [ ] 服务端 AUTH_PROOF 真实 Ed25519 验签和 pairingSecret 证明仍在 TODO 中，后续安全收口必须完成。

### Deferred Items

- 正式剪贴板实时同步 ready 状态：需要先完成 authenticated peer session lifecycle、ConnectionManager 和同步分发。
- 设备重命名、移除和空间 key rotation UI：依赖 trusted device 列表和 revoke/rotation 协议。
- mDNS 自动连接到正式配对设备：当前仍有 POC/manual IP 连接路径，正式发现和重连策略待 D4/H5 阶段推进。

## Context for Resuming Agent

## Important Context

下一个 agent 应从当前干净的 `main` 分支继续，最近提交 `f8d4a05` 已包含本阶段主要改动。用户上一轮真机测试已经能到“已认证”，本阶段目的是让它继续完成“配对已保存”。关键行为是：Harmony 在 `AUTH_OK` 后不落库，只保留内存 `ProtocolTransportSession`；当桌面端紧接着发 encrypted `SPACE_KEY_ROTATED` 时，Harmony 解密、校验、清零明文字节，并用 transaction 保存 space key alias 和 trusted desktop device。当前仍不是最终安全实现，因为 `spaceKey` 还没有真实导入 HUKS，只是通过 alias 占位表达目标存储引用。后续不要把这个占位误标为 HUKS 完成。

### Assumptions Made

- 桌面端已有默认同步空间，并且该空间 key 能从 Windows Credential Manager 边界加载。
- `SPACE_KEY_ROTATED` 可以承载初始邀请配对后的 key delivery，`delivery: pairing-v1` 用于区分该用途。
- Harmony 端可以先完成 RDB alias 占位和事务链路，再单独接真实 HUKS import。
- 当前用户测试环境使用手动 IP/端口触发配对；mDNS/VPN/TUN 问题不在本阶段解决范围内。

### Potential Gotchas

- 不要把真实 `spaceKey`、邀请 URI、pairingSecret、剪贴板正文或完整帧写进 handoff、日志、测试快照或聊天。
- 桌面端 `build_space_key_delivery_frame` 会临时把 key 放入内存 payload 进行 AEAD 加密，之后会清零本地 `space_key` buffer；不要添加调试输出。
- Harmony 端 `decoded.fill(0)` 只是清零解码后的字节数组；真实 HUKS import 之前不要声称 key 已安全保存。
- 如果 Harmony 端收到 `AUTH_OK` 后 UI 停在“配对握手已认证”，优先检查桌面端是否发送了第二帧 `SPACE_KEY_ROTATED`、Harmony 是否使用 `protocolSessionProvider` 切到了 authenticated decoder。
- `RdbCommandRunner.executeTransaction` 是同步 begin/commit/rollback 包裹 async execute；后续如果扩展复杂事务，注意 ArkTS 异常处理 warnings 和 rollback 路径。
- 当前 `.claude/handoffs/2026-07-05-200808-eggclip-space-key-delivery.md` 本身是未提交工作区改动；如果要保留到版本库需用户明确要求。

## Environment State

### Tools/Services Used

- Windows PowerShell in `D:\Develop\eggclip`.
- Rust/Cargo under `desktop/src-tauri`.
- pnpm/Svelte check and Vite build under `desktop`.
- DevEco hvigor under `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`.
- `session-handoff` skill scaffold/validator from `C:\Users\caozhipeng\.agents\skills\session-handoff`.

### Active Processes

- No dev server or long-running watcher was intentionally left running by this handoff creation step.

### Environment Variables

- `PYTHONUTF8` was used for handoff scaffold/validation compatibility on Windows.
- `JAVA_HOME` and `DEVECO_SDK_HOME` are required for Harmony hvigor commands.
- No secret environment variable values are captured here.

## Validation Performed

- `node .\protocol\scripts\validate-fixtures.mjs` -> passed.
- `cd desktop\src-tauri; cargo fmt -- --check` -> passed.
- `cd desktop\src-tauri; cargo test` -> passed, 117 tests.
- `cd desktop; pnpm check` -> passed, 0 errors/warnings.
- `cd desktop; pnpm build` -> passed.
- `cd harmony; hvigorw.bat test --no-daemon` -> passed with existing ArkTS warnings.
- `cd harmony; hvigorw.bat assembleHap --no-daemon` -> passed with existing ArkTS warnings.

## Related Resources

- [Previous handoff](./2026-07-05-153517-eggclip-harmony-x25519-ed25519-auth-proof.md)
- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `protocol/README.md`
- `protocol/test-vectors/sync/encrypted-space-key-rotated-envelope.valid.json`
- `desktop/src-tauri/src/transport/mod.rs`
- `harmony/entry/src/main/ets/store/PairingConnectionStore.ets`
- `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets`

---

**Security Reminder**: This handoff intentionally avoids raw invitation text, pairing secrets, private keys, clipboard content, production space keys, and signing material.
