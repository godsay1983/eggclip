# Handoff: EggClip 正式同步接线与 TODO 重整

## Session Metadata

- Created: 2026-07-11 13:38:21
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: 长会话，多轮 HarmonyOS 正式同步实现与计划重整。

### Recent Commits (for context)

- `7c161a3` SYNC_HEADS payload 解析与校验。
- `2a3816f` 设备页展示已持久化可信设备。
- `c11889f` 首页认证会话状态优先于 POC 状态。
- `bf761a4` 空间密钥自检扩展 AES-GCM 与 HMAC。
- `e12f15e` PasteButton 接入正式加密发送路径。
- `08e40bd` 正式本地出站事务服务。

## Handoff Chain

- Continues from: [2026-07-05-224734-eggclip-huks-space-key-selftest.md](./2026-07-05-224734-eggclip-huks-space-key-selftest.md)
- Supersedes: 前述交接后的正式同步开发上下文。

## Current State Summary

桌面端与 HarmonyOS 已完成基于邀请的配对、同一 WebSocket 会话内认证、初始空间密钥交付，以及实时 `ITEM_LIVE` 的基础双向接线。桌面本机复制会异步保存并向唯一认证空间发送；Harmony PasteButton 在认证会话存在时优先走正式本地事务、HUKS HMAC、HUKS 本地加密和加密 `ITEM_LIVE`，未认证时仍回退 POC。当前重点转为可靠连接、重连和补同步；尚未实现应用重启后自动恢复已配对设备会话。

## Codebase Understanding

### Architecture Overview

- Rust/Tauri 负责 Windows 剪贴板、SQLite、Credential Manager、配对服务端和 WebSocket。
- ArkTS/HarmonyOS 负责前台 UI、RDB、HUKS、PasteButton 和客户端配对会话。
- `protocol/` 只放 schema、说明和跨端向量；两端各自实现运行时。
- 网络会话密钥保护帧；空间密钥保护本地 RDB 正文。不要混用职责。

### Critical Files

| File | Purpose | Relevance |
|---|---|---|
| `AGENTS.md` | 产品、安全和工程约束 | 开发前必读 |
| `DESKTOP_DEVELOPMENT_TODO.md` | 桌面阶段化清单 | 已重整，后续只勾选既有项 |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony 阶段化清单 | 当前执行来源 |
| `desktop/src-tauri/src/transport/mod.rs` | 桌面认证会话与 ITEM_LIVE | 正式桌面出站/入站 |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Harmony 配对、认证会话和正式发送编排 | 正式会话核心 |
| `harmony/entry/src/main/ets/services/sync/OutboundItemLiveService.ets` | Harmony 本地事务与 ITEM_LIVE payload | PasteButton 正式出站 |
| `harmony/entry/src/main/ets/services/sync/InboundItemLiveService.ets` | Harmony 正式入站落库 | 不自动写剪贴板 |
| `harmony/entry/src/main/ets/services/crypto/SpaceKeyHuksService.ets` | AES 本地加密与 HMAC 别名 | 真机 HUKS 验收重点 |
| `harmony/entry/src/main/ets/services/transport/ProtocolTransportSession.ets` | ArkTS 加密帧、计数器与 replay guard | SYNC_HEADS/业务帧后续接线 |

### Key Patterns Discovered

- Pages 不直接访问 RDB、WebSocket 或 HUKS；经 store/service 调用。
- 本地剪贴板必须先持久化，网络失败不得回滚或阻塞用户操作。
- Harmony 不得静默读取剪贴板；只能由真实 PasteButton 授权。
- 正式业务帧只能在 authenticated session 中发送；POC 状态不得冒充可信连接。
- 普通日志、UI 与 handoff 不得写入正文、邀请秘密、密钥、摘要或完整帧。

## Work Completed

### Tasks Finished

- [x] 桌面认证 `ITEM_LIVE` 入站与本机监听后的出站。
- [x] Harmony 配对、AUTH_OK、空间密钥 HUKS 导入、认证 `ITEM_LIVE` 入站与 PasteButton 正式出站。
- [x] HUKS AES-GCM 与 HMAC 摘要别名、自检 UI、正式会话状态与可信设备列表。
- [x] SYNC_HEADS payload 的 ArkTS 基础校验。
- [x] 两份 TODO 重整为简明阶段化清单。

### Files Modified but Not Committed

| File | Changes | Rationale |
|---|---|---|
| `DESKTOP_DEVELOPMENT_TODO.md` | 完整重整 | 删除开发日志式细节，只保留可验收项 |
| `HARMONY_DEVELOPMENT_TODO.md` | 完整重整 | 后续开发的唯一阶段化清单 |
| `.claude/handoffs/2026-07-11-133821-eggclip-formal-sync-and-todo-rebaseline.md` | 本交接文档 | 保存续接上下文 |

### Decisions Made

| Decision | Options Considered | Rationale |
|---|---|---|
| TODO 不再记录细节实现 | 继续追加子项；改为阶段清单 | 用户要求以 TODO 驱动开发，细节项会扭曲完成度 |
| Harmony HMAC 使用同一空间密钥上下文的独立 HUKS alias | 在 RDB 保存裸 key；不做 HMAC | 保持与桌面 HMAC 规则一致且不暴露空间密钥 |
| 未认证时保留 POC 回退 | 强制正式发送；完全移除 POC | 保护现有测试路径，同时不伪造正式同步 |

## Pending Work

### Immediate Next Steps

1. 严格按 D4/H5 既有 TODO 实现已配对设备的正式连接生命周期：前台自动连接、单连接去重、心跳与重连。
2. 接入 `SYNC_HEADS` 实际发送、范围请求、`ITEM_BATCH`、ACK 与 retention gap。
3. 用 HarmonyOS 6.1 真机重新配对，运行“空间密钥与摘要自检”，再验证 PasteButton 到桌面端的正式实时发送。

## Immediate Next Steps

1. 按现有 H5/D4 TODO 实现已配对设备的正式连接生命周期，不新增 TODO 项。
2. 连接生命周期稳定后接入既有的 `SYNC_HEADS`、范围请求、`ITEM_BATCH`、ACK 与 retention gap 项。
3. 在真机重新配对后验收 HUKS HMAC 自检和 Harmony → 桌面实时发送。

### Blockers/Open Questions

- 真机 HUKS HMAC-SHA-256 的实际输出尚未与桌面端互通验收；旧配对没有 HMAC alias，需要重新配对。
- 应用重启后的 trusted-device 正式握手/重连尚未设计完成，不能声称已有自动恢复。

### Deferred Items

- 历史正文解密预览、设备重命名/移除/密钥轮换、平板双栏、发布准备均保留在既有 TODO，暂不跨阶段实现。

## Context for Resuming Agent

### Important Context

必须先读 `AGENTS.md` 和两份重整后的 TODO。用户明确要求：后续开发只依据 TODO 推进，完成既有项后打勾，不再向 TODO 增加实现细节或新子项。若需要记录实现过程，写 handoff 或提交说明。不要自动提交、推送或创建分支；虽然本会话出现过自动生成的提交，仍应遵守该约束。

## Important Context

后续开发的唯一计划来源是重整后的 `DESKTOP_DEVELOPMENT_TODO.md` 与 `HARMONY_DEVELOPMENT_TODO.md`。TODO 已从开发日志收敛为可验收阶段清单；只勾选既有项，禁止新增细碎实现项。正式同步目前只覆盖当前配对产生的认证会话，可靠重连与补同步仍未完成，不能对用户表述为“应用重启后可自动同步”。

### Assumptions Made

- v1 只同步 `text/plain`，单条不超过 256 KiB，纯局域网且不含云服务。
- Harmony 仅前台发现/连接，接收后用户点击复制，发送只能经过 PasteButton。
- 认证会话只在当前配对 WebSocket 生命周期内有效。

### Potential Gotchas

- Harmony HUKS 行为必须以真机验收为准，模拟器不能替代。
- `PairingConnectionStore` 当前保留的 session 是配对流程产生的；没有 ConnectionManager 时应用重启后不会自动重建。
- `ITEM_LIVE` 与 `ITEM_BATCH` 必须分流，批量历史不得覆盖系统剪贴板。
- ArkTS 禁止 `Object.prototype`、`Function.call/apply` 等 JavaScript 写法；使用 ArkTS 兼容的直接映射访问。
- 运行 `hvigorw` 前设置 `JAVA_HOME`、`DEVECO_SDK_HOME`，并将 JBR 的 `bin` 加入 `Path`。

## Environment State

### Tools/Services Used

- `pnpm`、Cargo、PowerShell、DevEco `hvigorw.bat`。
- Harmony 验证命令：`hvigorw.bat test --no-daemon` 与 `assembleHap --no-daemon`。

### Active Processes

- 无需保留的开发服务或后台进程。

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`

## Related Resources

- `docs/EggClip最佳实现方案.md`
- `protocol/README.md`
- `protocol/v1.schema.json`
- `protocol/test-vectors/`
- `docs/MANUAL_REGRESSION.md`

---

本交接文档不包含邀请、正文、密钥、摘要、签名材料或本机签名配置。
