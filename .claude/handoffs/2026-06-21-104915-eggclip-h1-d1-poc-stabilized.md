# Handoff: EggClip D1/H1 双端 POC 稳定化完成

## Session Metadata

- Created: 2026-06-21 10:49:15
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 本次 handoff 续接约 15 分钟；代码状态来自上一轮双端 POC 开发完成后的工作区。

### Recent Commits (for context)

- f9a2947 feat: 实现 POC 连接生命周期管理，包括超时、断开按钮、页面销毁清理和消息大小校验
- f4ac6ea feat: 实现桌面端断开连接清理和鸿蒙端手动复制到本机功能
- cbe13af feat: 完成桌面↔Harmony双向文本传输POC
- 68ec90f feat: 实现HarmonyOS到桌面端的POC文本传输
- 77cefe9 feat: 实现WebSocket POC服务器和HarmonyOS剪贴板读取

## Handoff Chain

- Continues from: [2026-06-20-214920-eggclip-two-sides-layering.md](./2026-06-20-214920-eggclip-two-sides-layering.md)
  - Previous title: EggClip 两端 Shell 分层基线完成
- Supersedes: None

Review the previous handoff for earlier shell layering, icon, and project setup context.

## Current State Summary

EggClip 当前已完成桌面端和 HarmonyOS 端的 D1/H1 手动局域网文本同步 POC：桌面端启动 WebSocket POC server，HarmonyOS 端可手动输入桌面 IP 和端口连接；HarmonyOS 通过真实 PasteButton 读取一次性授权后的纯文本并发送到桌面端；桌面端可把当前文本广播给已连接的 HarmonyOS POC peer；HarmonyOS 收到桌面文本后只显示预览，用户点击“复制到本机”后才写入系统剪贴板。当前 `git status` 只有本 handoff 文档未跟踪，功能代码已经在最近提交中。

## Architecture Overview

项目继续保持桌面端 Tauri/Svelte 与 HarmonyOS ArkUI 的分层约束。桌面端 Rust 的 `transport` 只负责 POC WebSocket 连接和帧收发，前端 store/API 负责 UI 编排；HarmonyOS 的 `WebSocketTransportService` 只处理连接、消息解析和发送，`HomePage` 负责页面状态与用户动作，`ClipboardBridgeService` 封装 PasteButton 授权后的读取和用户触发写入。当前 POC 使用临时明文 JSON `{ "kind": "clipboardText", "text": "..." }`，还不是最终加密协议。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| desktop/src-tauri/src/transport/mod.rs | 桌面 POC WebSocket server、peer 管理、clipboardText JSON 收发和测试 | 后续协议化、连接生命周期和帧限制都要从这里演进 |
| desktop/src-tauri/src/clipboard/mod.rs | 桌面剪贴板监听、读写、回环抑制基础能力 | 后续远端在线事件自动写入 Windows 剪贴板时必须复用这里的策略 |
| desktop/src/lib/stores/shell.ts | 桌面 UI 状态编排和 POC 发送动作 | 前端不要绕过 store 直接调用底层能力 |
| desktop/src/lib/components/clipboard/ClipboardCard.svelte | 桌面当前剪贴板卡片和发送到 Harmony POC 的入口 | 当前可见功能主要集中在这里 |
| harmony/entry/src/main/ets/pages/HomePage.ets | HarmonyOS 首页、PasteButton、手动连接、收发预览、复制到本机 | 目前 H1 POC 主要页面，后续需要继续拆薄 |
| harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets | HarmonyOS POC WebSocket 连接、超时、关闭、消息校验 | 下一步 mDNS 和最终 transport 都会接入这里或替换这里 |
| harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets | HarmonyOS PasteButton 授权读取和用户触发写入 pasteboard | 不能改成静默读取剪贴板 |
| HARMONY_DEVELOPMENT_TODO.md | HarmonyOS 阶段计划和当前 H1 状态 | 继续开发时按 TODO 勾选推进 |
| DESKTOP_DEVELOPMENT_TODO.md | 桌面端阶段计划 | D1 剩余项和 D2 入口在这里 |
| docs/EggClip最佳实现方案.md | 产品、协议、安全和平台边界 | 改协议或安全假设前先同步这里 |

## Key Patterns Discovered

- POC 阶段坚持“可见可测但不越界”：可以做手动 IP、临时 JSON 和明文局域网 POC，但不能把它误认为最终协议。
- HarmonyOS 剪贴板读取必须由真实 ArkUI PasteButton 触发；普通按钮或后台静默读取都不符合 v1 边界。
- 收到远端文本后，桌面端当前 POC 只展示 Harmony 来源；HarmonyOS 端只展示桌面来源，写入本机剪贴板必须由用户点击触发。
- WebSocket 连接层只负责连接和帧处理，不决定“是否写入系统剪贴板”；同步策略后续放到 sync 层。
- 日志和错误提示不能输出剪贴板正文、邀请信息、密钥、摘要或完整网络帧。

## Work Completed

### Tasks Finished

- [x] 桌面端 POC server 支持 HarmonyOS 连接、断开清理和 peer 广播。
- [x] 桌面端支持发送当前文本到 HarmonyOS POC peer。
- [x] 桌面端支持接收 HarmonyOS 的 `clipboardText` POC 消息并在 UI 中展示来源。
- [x] HarmonyOS 端支持手动输入桌面 IP 和端口连接 POC server。
- [x] HarmonyOS 端支持连接超时、主动断开、页面销毁关闭和基础 JSON 校验。
- [x] HarmonyOS 端 PasteButton 授权读取纯文本后可发送到桌面。
- [x] HarmonyOS 端收到桌面 POC 文本后只展示预览，用户点击后才复制到本机。
- [x] 更新 HarmonyOS TODO，标记 H1 POC 已完成的连接、收发和剪贴板约束。
- [x] 桌面端和 HarmonyOS 端最近一轮自动化验证通过。

## Files Modified

当前工作区除本 handoff 文档外没有未提交的功能代码改动。最近功能改动已经体现在 `f9a2947` 到 `77cefe9` 这一组提交中。

| File | Changes | Rationale |
|------|---------|-----------|
| .claude/handoffs/2026-06-21-104915-eggclip-h1-d1-poc-stabilized.md | 新增本次交接文档 | 保存当前双端 POC 状态、验证结果和下一步 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| H1 POC 先使用手动 IP 和端口 | 立即做完整 mDNS 自动发现，或先做手动连接 | 手动连接能先验证双端 WebSocket 和剪贴板链路，mDNS 留到下一步按 SDK API 精确实现 |
| POC 消息保持临时 JSON 明文 | 立即实现最终加密协议，或先用临时帧 | 当前目标是双端可见链路；最终协议需要 protocol schema、测试向量、Rust/ArkTS 类型一起推进 |
| HarmonyOS 收到远端文本后不自动写入 pasteboard | 自动写入，或只展示并要求用户点击 | 符合 HarmonyOS 平台边界和 EggClip v1 的用户授权模型 |
| 页面销毁时主动关闭 HarmonyOS POC WebSocket | 依赖系统回收，或显式关闭 | 前台连接边界更清晰，避免页面退出后仍保留 POC 连接 |
| 桌面端当前不把 HarmonyOS POC 消息自动写入 Windows 剪贴板 | 立刻自动写入，或先展示来源 | 避免在 POC 阶段绕过同步策略和回环抑制；后续应在 sync 层接入 |

## Immediate Next Steps

1. 从 H1 剩余计划继续：核对已安装 HarmonyOS SDK 的 mDNS API，设计 `_eggclip._tcp.local.` 发现服务的最小封装和页面状态。
2. 实现 HarmonyOS mDNS 发现候选地址列表，并让手动 IP 保留为 fallback；注意前台生命周期清理和重复设备去重。
3. 回到桌面 D1 收尾：把远端在线事件自动写入 Windows 剪贴板的策略接到 sync 层，同时复用现有回环抑制，确保离线补齐不覆盖系统剪贴板。
4. 如果要进入 D2/H2，先补 `protocol/` schema 与测试向量骨架，避免临时 JSON POC 演变成隐式协议。

## Blockers/Open Questions

- HarmonyOS mDNS 的实际 ArkTS API 需要基于本机 DevEco SDK 核对；不要凭记忆写接口。
- 桌面端 Windows 防火墙和局域网互通需要真机手动验证；Codex 内部自动化无法完整替代。
- HarmonyOS PasteButton 静态检查会提示读取 pasteboard 相关权限，但当前运行路径依赖 PasteButton 用户授权；后续真机验收要确认行为。
- 最终协议尚未创建跨语言测试向量；不能开始混入加密握手字段而不更新方案和 TODO。

## Deferred Items

- mDNS 自动发现：已计划但尚未实现，下一轮优先处理。
- 最终加密握手、设备身份、邀请配对和会话密钥：属于协议阶段，不能在 POC 代码中零散加入。
- 历史存储、retention 和 SQLite/RDB migration：属于 D2/H2 数据层阶段。
- Windows 开机启动、托盘细节和安装包：桌面端后续阶段处理。
- 跨端互通测试向量：protocol 目录建立后推进。

## Important Context

继续开发前必须先读 `AGENTS.md`、`docs/EggClip最佳实现方案.md`、`DESKTOP_DEVELOPMENT_TODO.md` 和 `HARMONY_DEVELOPMENT_TODO.md`。EggClip v1 是纯局域网文本剪贴板同步，不做账号、云同步、公网中继或多格式剪贴板。HarmonyOS 端不能静默读取剪贴板，只能通过真实 PasteButton 获得一次性读取授权；远端文本写入本机也必须由用户动作触发。当前 POC 使用的 `clipboardText` JSON 只是临时链路验证，不具备身份认证、加密、防重放或最终兼容性，下一步不能把它扩展成事实协议，应该先建立 `protocol/` 的 schema 和测试向量。

## Assumptions Made

- Windows 是 v1 桌面端唯一承诺平台；其他平台不在当前验收范围内。
- HarmonyOS v1 继续以 SDK 6.1.1(24)、compatible 6.1.0(23)、phone/tablet 为目标。
- 当前最近提交已经代表功能代码基线；本轮 handoff 没有修改功能代码。
- 本地 DevEco Studio 和 Rust/Node/pnpm 工具链仍与上一轮验证环境一致。

## Potential Gotchas

- `pnpm tauri dev` 如果受 VPN 影响，Vite/Tauri dev URL 应继续使用 `127.0.0.1`，不要回退到 `localhost`。
- HarmonyOS manifest 不应新增普通三方应用拿不到的剪贴板读取权限；PasteButton 是产品和平台边界。
- 不要在 `harmony/` 下面再创建嵌套 DevEco 工程；现有 `harmony/` 就是工程根。
- `harmony/build-profile.json5` 属于本机签名相关配置，处理时不要输出或提交本机敏感配置。
- 当前 POC frame limit 和业务 text limit 是两层限制：帧限制 1 MiB，剪贴板正文限制 256 KiB。
- 收到远端内容后写入本机剪贴板时必须防同步回环；桌面端已有回环抑制基础，但 POC 接收路径尚未自动写入。

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Git on branch `main`
- Node/pnpm for desktop Svelte/Tauri frontend
- Rust/Cargo for Tauri backend
- DevEco Studio bundled JBR and hvigor for HarmonyOS build/test

### Active Processes

- 本次 handoff 未启动持续运行的 dev server、WebSocket server、hvigor daemon 或 Tauri dev 进程。

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Validation Snapshot

上一轮功能开发完成后的已知验证结果：

- `pnpm check` passed
- `pnpm test` passed
- `pnpm build` passed
- `cargo fmt -- --check` passed
- `cargo check` passed
- `cargo test` passed，12 tests passed
- HarmonyOS `hvigorw.bat test --no-daemon` passed
- HarmonyOS `hvigorw.bat assembleHap --no-daemon` passed
- `git diff --check` passed，仅有 CRLF 提示

本次 handoff 前重新确认：

- `git status --short --branch` 显示功能代码无未提交改动，只有本 handoff 文档未跟踪。
- `git log --oneline -5` 与上方 Recent Commits 一致。

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `desktop/README.md`
- `.claude/handoffs/2026-06-20-214920-eggclip-two-sides-layering.md`

---

Security reminder: rerun the handoff validator after editing this document.
