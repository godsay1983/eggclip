# Handoff: EggClip Harmony HUKS 空间密钥自检通过

## Session Metadata

- Created: 2026-07-05 22:47:34
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 约 2 小时

### Recent Commits (for context)

- 9207827 feat: 配对完成持久化分阶段执行，数据库基线列，HUKS加密重试，设置页诊断UI
- 8a0c5b6 feat: 新增 HUKS 空间密钥加解密自检服务及设置页诊断入口
- 1b86920 feat: 实现 HUKS AES-GCM 加解密并更新开发清单
- 6ec68cc feat: 接入SpaceKeyHuksService并完成HUKS导入集成
- db5a71f feat: 新增SpaceKeyDeliveryService，重构配对连接中的密钥交付校验

## Handoff Chain

- **Continues from**: [2026-07-05-200808-eggclip-space-key-delivery.md](./2026-07-05-200808-eggclip-space-key-delivery.md)
  - Previous title: EggClip 配对后加密下发空间密钥
- **Supersedes**: 2026-07-05-200808-eggclip-space-key-delivery.md 的“空间密钥保存和真机自检待验证”部分。

## Current State Summary

本轮重点完成 Harmony 真机配对后 `SPACE_KEY_ROTATED` 空间密钥落地链路的排障和收口。用户在真机上依次遇到本机设备 ID、RDB `spaces` 写入、HUKS AES-GCM 自检失败等问题；当前最新状态是：真机配对已成功，设置页“空间密钥自检”已通过，说明 `SPACE_KEY_ROTATED` 解密、HUKS `spaceKey` import、RDB 保存同步空间/可信设备、HUKS AES-GCM 加密解密往返都已打通。工作区当前干净，相关修改已在最近提交 `9207827` 中。

## Codebase Understanding

## Architecture Overview

Harmony 端配对链路现在是：

1. `PairingPage` 负责邀请导入、确认码确认、IP/端口输入和用户操作入口。
2. `PairingConnectionStore` 编排 WebSocket 配对握手、`CLIENT_HELLO`、`AUTH_PROOF`、`AUTH_OK`、`SPACE_KEY_ROTATED` 处理。
3. `SpaceKeyDeliveryService` 校验并解密桌面端下发的空间密钥包，只把 `huks://` key ref 交给持久化层。
4. `SpaceKeyHuksService` 把明文 32 字节 `spaceKey` 导入 HUKS，并通过 HUKS AES-GCM 做后续加解密。
5. `PairingRdbRepository` 在同一个 transaction 中保存 `spaces` 和 `devices`；失败会拆成 `space` / `device` 阶段。
6. `SettingsPage` 通过 `SpaceKeyCryptoSelfTestService` 对最新 active space key ref 做 HUKS 加解密自检，不展示明文、密文、tag 或 key ref。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Harmony 配对网络状态机和落库编排 | 已新增配对完成持久化阶段诊断，下一步业务同步会复用认证 session/可信设备状态 |
| `harmony/entry/src/main/ets/services/pairing/SpaceKeyDeliveryService.ets` | 处理 `SPACE_KEY_ROTATED` payload | 已负责校验 spaceId/keyVersion/delivery/key length，并清零明文 key buffer |
| `harmony/entry/src/main/ets/services/crypto/SpaceKeyHuksService.ets` | HUKS 空间密钥 import、AES-GCM 加解密 | 真机已验证自检通过；保留 `AE_TAG_LEN=128/16` fallback 和阶段错误诊断 |
| `harmony/entry/src/main/ets/services/crypto/SpaceKeyCryptoSelfTestService.ets` | 设置页空间密钥自检业务服务 | 真机自检通过，后续可作为 HUKS 回归入口 |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | 真实 RDB repository | `PairingRdbRepository.persistCompletion` 已拆分 space/device 阶段并回滚 |
| `harmony/entry/src/main/ets/data/repositories/RepositoryCommands.ets` | SQL command 生成 | `spaces`/`devices` upsert 已规避 null 参数绑定问题 |
| `harmony/entry/src/main/ets/data/db/MigrationRunner.ets` | RDB migration 和开发期 schema repair | 已新增 baseline columns 检测和非破坏性补列，解决旧真机数据库缺列问题 |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | 设置页 UI 和诊断反馈 | 空间密钥自检结果现在可见，失败会显示安全阶段信息 |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony 开发计划事实记录 | 已记录配对落库和 HUKS 自检链路进展 |

## Key Patterns Discovered

- HUKS/RDB 错误面向用户时只显示动作和安全阶段，不能展示 key ref、密钥、密文、tag、正文、完整帧。
- Harmony RDB 真机对参数绑定更敏感；`undefined/null` 可选字段在 `spaces`/`devices` upsert 中改为 SQL `NULL` 字面量，避免绑定 `null`。
- 开发期真机可能保留旧 RDB 表结构；`CREATE TABLE IF NOT EXISTS` 不会补列，所以 `MigrationRunner.ensureBaselineColumns` 做非破坏性补列。
- HUKS AES-GCM 在真机上需要更宽容的参数处理：`HUKS_TAG_IV` 与 nonce 同值，并尝试 `AE_TAG_LEN=128` 和 `AE_TAG_LEN=16` 两种单位。
- ArkTS 禁止 `any/unknown`、`in` 操作符和索引访问字段；错误码提取使用 `JSON.stringify(error)` 后正则解析。

## Work Completed

## Tasks Finished

- [x] 定位并修复 Harmony 真机配对后“无法读取或写入本机设备 ID”的身份 metadata 问题。
- [x] 定位并修复 `spaces` 写入失败：新增旧表 schema repair，避免旧开发版 RDB 缺列导致配对完成落库失败。
- [x] 修复 `spaces`/`devices` upsert 可选字段绑定 null 的真机兼容问题。
- [x] 将配对完成持久化失败拆成 HUKS、space、device、RDB fallback 多阶段用户提示。
- [x] `SpaceKeyHuksService.importSpaceKey` 改为幂等，HUKS key 已存在时返回成功，支持“导入成功但 RDB 落库失败后重试”。
- [x] 设置页空间密钥自检 UI 可见化，显示通过/失败、阶段、更新时间和安全说明。
- [x] 调整 HUKS AES-GCM 参数，新增 `HUKS_TAG_IV`，增加 `AE_TAG_LEN=128/16` fallback 和阶段错误诊断。
- [x] 用户真机确认：配对成功，空间密钥 HUKS 加解密自检通过。

## Files Modified

当前工作区干净，相关修改已提交在 `9207827`。该提交主要覆盖：

| File | Changes | Rationale |
|------|---------|-----------|
| `HARMONY_DEVELOPMENT_TODO.md` | 标记配对落库诊断和 HUKS 自检进展 | 保持计划文档与真实功能状态一致 |
| `harmony/entry/src/main/ets/data/db/MigrationRunner.ets` | 新增 baseline column repair | 兼容旧真机 RDB 表结构 |
| `harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets` | 配对完成 transaction 拆分 space/device 阶段 | 精确定位落库失败阶段 |
| `harmony/entry/src/main/ets/data/repositories/RepositoryCommands.ets` | `spaces`/`devices` upsert 避免绑定 null | 修复真机 RDB 参数兼容问题 |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | 增强空间密钥自检结果展示 | 用户能看到诊断状态和安全阶段 |
| `harmony/entry/src/main/ets/services/crypto/SpaceKeyHuksService.ets` | HUKS import 幂等、AES-GCM 参数和诊断增强 | 真机 HUKS 自检通过的核心修复 |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | 配对完成失败描述细化 | 避免“写入失败”泛化提示 |
| `harmony/entry/src/test/LocalUnit.test.ets` | 更新参数契约和 null 绑定测试 | 覆盖关键 command 与 HUKS 参数形状 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| 旧 RDB 表采用非破坏性补列，不要求用户清应用数据 | 清数据重配；新 migration 版本；启动期 repair | 当前仍是开发期且表结构已有设备留存，补列能保留真机测试状态，风险低 |
| 配对完成落库拆成 space/device 两阶段 | 保持单条 transaction 黑盒；拆分两个独立 transaction；单 transaction 内分阶段 | 仍保持原子性，同时能向用户报告准确失败点 |
| HUKS import 已存在时视为成功 | 每次强制覆盖；遇到已存在即失败；先检查存在 | 重试配对时可能 HUKS 已导入但 RDB 未保存，幂等处理避免死锁 |
| HUKS AES-GCM 支持 `AE_TAG_LEN=128/16` fallback | 固定 128；固定 16；两者尝试 | 真机兼容性优先，当前自检已通过；保留 fallback 不泄露敏感数据 |
| HUKS 错误码通过 JSON 序列化安全提取 | 直接访问 `error.code`；`any`；JSON 正则 | 符合 ArkTS 限制，不引入 `any/unknown` |

## Pending Work

## Immediate Next Steps

1. 进入下一阶段：将 `encryptedSpaceKeyRef` 接入正式业务帧加解密，优先 Harmony 端 `ITEM_LIVE` 接收/解密/入库链路。
2. 桌面端与 Harmony 端对齐“已配对设备 + session/space key”后的正式连接生命周期，逐步替换 POC 手动连接。
3. 补充 Rust ↔ ArkTS 协议互通测试，覆盖 `ITEM_LIVE` / `ITEM_BATCH` 的 AEAD 加解密、重放、乱序和超限帧。

## Blockers/Open Questions

- [ ] 桌面端当前是否已经完整使用配对后的 trusted device/session 状态来驱动正式同步，还需要复查。
- [ ] Harmony 业务帧加解密应优先直接使用 HUKS `spaceKey`，还是先用 session key 只做在线通道加密，需要按 `docs/EggClip最佳实现方案.md` 核对。
- [ ] 设备移除和空间密钥轮换还未完成，不能把多设备长期同步视为已闭环。
- [ ] 真机通过的是设置页小文本自检；正式剪贴板正文仍需验证 256 KiB 上限、分段/性能和错误提示。

## Deferred Items

- 自动发现已配对桌面端并自动连接：待正式连接生命周期接入后再做。
- 设备列表真实 trusted device 展示、重命名、移除和轮换影响提示：待配对记录查询和设备管理 UI 接入。
- Harmony 端正式 `PasteButton` 发送后的 `ITEM_LIVE` 广播：待业务帧加密发送路径可用。
- 桌面端完整收发回环抑制和离线补齐策略：需要和正式同步 service 一起验证。

## Context for Resuming Agent

## Important Context

用户刚刚在 Harmony 真机确认“配对成功 + 空间密钥加解密自检通过”。这是一个重要里程碑：之前 `SPACE_KEY_ROTATED` 已能从桌面端到 Harmony，HUKS key import 能成功，RDB 能保存同步空间和可信设备记录，设置页 HUKS AES-GCM 自检也已通过。不要继续在配对/HUKS import/RDB space 写入上重复排障，除非用户提供新的报错。下一步应该从“配对后如何使用密钥做正式剪贴板业务帧加解密和同步”开始。

## Assumptions Made

- 当前真机是 HarmonyOS 6.1 设备，用户能安装最新 HAP 并实际运行设置页自检。
- 当前 HUKS AES-GCM 小文本自检通过足以证明 alias/ref 可用，但不等于正式业务同步已完成。
- 当前提交 `9207827` 已包含本轮修复，工作区干净；如继续开发，先确认 `git status --short`。
- 协议和安全边界仍以 `AGENTS.md` 与 `docs/EggClip最佳实现方案.md` 为准。

## Potential Gotchas

- 不要把设置页自检通过解读为“剪贴板同步完成”；它只验证空间密钥 HUKS 加解密可用。
- Harmony 端仍不能静默读取系统剪贴板，发送必须由 `PasteButton` 授权触发。
- 普通日志和 UI 不能展示剪贴板正文、邀请 secret、密钥、key ref、完整密文、tag 或完整帧。
- 如果未来修改 HUKS 参数，必须真机验证；模拟器结果不能替代 HUKS/mDNS/WebSocket/PasteButton 真机验收。
- 当前 `MigrationRunner.ensureBaselineColumns` 是开发期兼容旧表的 repair，不应替代未来正式可审计 migration 体系。
- ArkTS 严格限制多：避免 `any`、`unknown`、`in`、属性索引访问、`Promise.finally` 等不兼容写法。

## Environment State

## Tools/Services Used

- DevEco Studio bundled JBR: `JAVA_HOME`
- DevEco SDK: `DEVECO_SDK_HOME`
- HAP/test command:
  - `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat test --no-daemon`
  - `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat assembleHap --no-daemon`
- Git branch: `main`
- Working tree at handoff creation: clean

## Active Processes

- No long-running development servers or background processes were started by this handoff turn.

## Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8` was used only to run the handoff scaffold script on Windows with UTF-8 output.

## Validation Performed

- `hvigor test --no-daemon`: passed during the HUKS diagnostic/fallback implementation.
- `hvigor assembleHap --no-daemon`: passed during the HUKS diagnostic/fallback implementation.
- `git diff --check`: no whitespace errors; only expected Windows CRLF warnings during checks.
- User true-device validation: pairing succeeded and space key encryption/decryption self-test passed.

## Related Resources

- [AGENTS.md](../../AGENTS.md)
- [HARMONY_DEVELOPMENT_TODO.md](../../HARMONY_DEVELOPMENT_TODO.md)
- [DESKTOP_DEVELOPMENT_TODO.md](../../DESKTOP_DEVELOPMENT_TODO.md)
- [docs/EggClip最佳实现方案.md](../../docs/EggClip最佳实现方案.md)
- [Previous handoff](./2026-07-05-200808-eggclip-space-key-delivery.md)

---

**Security Reminder**: This handoff intentionally avoids secrets, invitation payloads, key refs, ciphertext, tags, clipboard content, certificate material, and local signing configuration values.
