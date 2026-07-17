# Handoff: EggClip Windows 互联 W2W-12 完成，待 W2W-13 真机验收

## Session Metadata

- Created: 2026-07-17 20:25:04
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: 跨多轮完成 Windows 客户端互联 W2W-01 至 W2W-12，本次交接收尾约 1 小时

### Recent Commits (for context)

- `2a621cf feat: 重新设计设备配对界面，添加图标与视觉细节`
- `4855edb feat: 实现桌面端加入配对对话框，支持候选地址选择与错误分类`
- `df1d7c4 feat: 区分协调端与成员端角色，支持成员端离开空间`
- `3f61d71 feat: 实现同空间实时事件安全转发`
- `1b9d747 feat: Windows双向自动同步及历史关闭确认`

## Handoff Chain

- **Continues from**: [2026-07-13-222537-eggclip-appgallery-remediation-h12-ready-for-regression.md](./2026-07-13-222537-eggclip-appgallery-remediation-h12-ready-for-regression.md)
  - Previous title: EggClip 鸿蒙上架整改完成 H-REVIEW-12，待双端真机回归
- **Supersedes**: None。上一份文档仍保留 HarmonyOS 上架整改背景；本交接是 Windows 客户端互联 Roadmap 的当前事实来源。

## Current State Summary

Windows 客户端互联 Roadmap 的 W2W-01 至 W2W-12 已完成并勾选：两台 Windows 已具备邀请配对、双向认证、空间落库、正式会话、可信重连、双向实时同步、离线补齐、同空间多设备转发、成员移除与密钥轮换，以及协调端/成员端 UI。最后完成的 W2W-12 补齐了自动化与发布安全门禁，并将完整邀请从 Svelte 状态移到 Rust 短期内存运行时。完整桌面门禁通过；下一项且唯一未完成的 Roadmap 任务是 W2W-13 双 Windows 与混合设备真机验收及文档收尾。

## Codebase Understanding

### Architecture Overview

- `desktop/src-tauri/src/pairing/` 负责邀请、配对握手和短期敏感材料生命周期；前端只拿到脱敏摘要和邀请 ID。
- `desktop/src-tauri/src/transport/` 负责服务端/客户端正式认证 WebSocket 会话；已认证会话统一进入 session registry。
- `desktop/src-tauri/src/sync/` 负责实时事件、补历史、ACK、转发、去重和剪贴板写入策略。
- `desktop/src-tauri/src/storage/` 负责空间、成员、可信路由、历史和同步头持久化。
- Svelte 的 `src/lib/api/` 只封装 command/event，`src/lib/stores/` 编排状态，组件不直接访问凭据、数据库或 socket。
- `protocol/` 是 Rust、ArkTS 以及 Rust 客户端/服务端共用的协议 schema 和测试向量事实来源。

### Critical Files

| File | Purpose | Relevance |
|---|---|---|
| `docs/Windows客户端互联剪贴板ROADMAP.md` | 13 个固定 W2W 任务及验收定义 | W2W-12 已完成，W2W-13 未完成；不要新增任务 |
| `docs/Windows客户端互联剪贴板实现方案.md` | Windows 客户端互联架构和安全方案 | 真机问题涉及协议或安全边界时先核对 |
| `desktop/src-tauri/src/pairing/mod.rs` | 邀请生成、短期邀请运行时、配对服务端/客户端 | 完整邀请不得重新进入前端或普通日志 |
| `desktop/src-tauri/src/transport/mod.rs` | 认证会话、主动连接和可信重连 | W2W-13 的重启、断网、IP 变化测试重点 |
| `desktop/src-tauri/src/storage/repositories.rs` | 空间、成员、可信设备和历史 repository | 离线补齐、移除和密钥轮换验收重点 |
| `desktop/src/lib/components/devices/PairingJoinDialog.svelte` | 加入另一台电脑的用户流程 | 验收邀请、确认码、候选地址与错误分类 |
| `desktop/src/lib/pairing-join.ts` | 加入对话框状态与角色权限纯函数 | Svelte 自动化覆盖入口 |
| `protocol/test-vectors/handshake/pairing-proof-v2.valid.json` | invitation v2 proof 共享向量 | Rust 客户端与服务端必须继续共用 |
| `scripts/release-safety-check.ps1` | 协议向量及敏感信息发布检查 | 提交或打包前必须执行 |
| `harmony/build-profile.json5` | 可共享的 Harmony 构建配置 | 当前已经脱敏，禁止写入本机签名材料 |

### Key Patterns Discovered

- 完整邀请、配对秘密和密钥只能在 Rust 短生命周期对象中存在；前端状态、数据库、日志和序列化 DTO 都不能保留。
- 生成邀请后，前端通过 `invitationId` 请求后端复制；二维码 SVG 可以表达邀请，但 DTO 不包含原始 URI。
- `PairingInvitationClipboardRuntime` 同时只保留一份邀请，按 TTL 过期，并在替换或销毁时执行内存清理。
- POC 连接只能用于诊断，不能显示成可信设备，也不能替代正式会话验收。
- 离线 `ITEM_BATCH` 只进入历史，不能覆盖当前系统剪贴板；`ITEM_LIVE` 才允许按设置实时写入。
- 同一 Roadmap 轮次完成一个完整任务，完成后勾选，开发期间不再追加新任务。

## Work Completed

### Tasks Finished

- [x] W2W-01 至 W2W-11：Windows 邀请配对、正式连接、同步、转发、轮换和产品界面均完成。
- [x] W2W-12 Rust 自动化覆盖：邀请解析、握手、migration、路由、会话、重连、同步、转发和轮换。
- [x] W2W-12 Svelte 自动化覆盖：加入流程、状态恢复、地址选择、角色权限和错误状态。
- [x] Rust 客户端和服务端消费同一个 pairing proof v2 共享测试向量。
- [x] 完整邀请从前端 DTO/store 移除，改由 Rust TTL 运行时按邀请 ID 安全复制。
- [x] 新增协议 fixture 校验和统一发布安全检查。
- [x] 脱敏共享 Harmony 构建配置，并补充本机签名恢复/再次净化说明。
- [x] W2W-12 Roadmap、桌面 README 和发布文档同步完成。

### Files Modified

| File | Changes | Rationale |
|---|---|---|
| `desktop/src-tauri/src/lib.rs` | 注册邀请复制短期运行时 | 让 command 共享受控的敏感材料生命周期 |
| `desktop/src-tauri/src/pairing/mod.rs` | DTO 跳过完整邀请；新增 TTL/清理运行时、按 ID 复制 command 和测试 | 防止邀请秘密进入前端状态或长期内存 |
| `desktop/src/lib/api/shell.ts` | 复制邀请 API 改收 `invitationId` | 不再传递原始邀请字符串 |
| `desktop/src/lib/stores/shell.ts` | store 复制动作改用邀请 ID | 与安全 DTO 边界一致 |
| `desktop/src/lib/types/shell.ts` | 删除前端邀请原文类型字段 | 阻止敏感材料进入类型化状态 |
| `desktop/src/lib/pairing-join.ts` | 增加空/就绪表单状态及角色权限纯函数 | 可测试且统一清空敏感输入 |
| `desktop/src/lib/components/devices/PairingJoinDialog.svelte` | 使用统一表单状态恢复/清理 | 关闭、取消、成功后不残留输入 |
| `desktop/src/routes/+page.svelte` | 按角色助手控制邀请与空间管理；复制使用邀请 ID | UI 与 Rust 权限校验保持一致 |
| `desktop/src/lib/shell.test.ts` | 增加状态恢复、材料清理和 owner/member 权限测试 | 完成 W2W-12 Svelte 覆盖 |
| `protocol/scripts/validate-fixtures.mjs` | 支持 pairing proof v2 fixture 校验 | 让共享协议向量进入发布门禁 |
| `scripts/release-safety-check.ps1` | 扫描前端敏感状态、Rust 敏感日志和协议 fixture | 防止正文、密钥、邀请或原始帧进入发布内容 |
| `desktop/README.md` | 记录 `pnpm release:check` 与安全门禁 | 给开发和发布提供统一入口 |
| `docs/RELEASE.md` | 增加 Harmony 本机签名恢复和再次脱敏流程 | 保持共享配置可提交且不泄露凭据 |
| `docs/Windows客户端互联剪贴板ROADMAP.md` | 完整勾选 W2W-12 | 同步可见进度，不添加新任务 |
| `harmony/build-profile.json5` | 移除共享文件中的本机签名材料 | 关闭发布安全门禁发现的风险 |

### Decisions Made

| Decision | Options Considered | Rationale |
|---|---|---|
| 前端只保存邀请 ID 与脱敏摘要 | 前端保存完整 URI；仅隐藏 UI；后端 TTL 运行时 | 隐藏 UI 不能阻止 devtools/state 泄露，后端短期持有边界最清晰 |
| 保留短期原始邀请直到过期 | 复制后立即删除；长期缓存；TTL 单实例缓存 | 用户可能需要重复复制，同时必须限制数量、时长并清理内存 |
| Rust 客户端/服务端共用 fixture | 两份独立测试数据；代码内常量；共享 JSON | 避免两端测试同时偏离协议事实来源 |
| 公共 Harmony build profile 保持脱敏 | 提交本机签名；删除构建配置；本地备份+恢复脚本 | 仓库安全与本机 DevEco 使用可兼得 |
| W2W-13 留给真机人工验收 | 用单机或自动测试代替；直接勾选 | VPN、防火墙、唤醒、多设备和剪贴板行为必须由真实设备验证 |

## Pending Work

唯一剩余开发里程碑是 W2W-13。它以人工真机回归为主，发现阻断缺陷时只在 Roadmap 的“阻断记录”中登记和关闭，不增加 W2W 任务。

## Immediate Next Steps

1. 准备两台 Windows 干净数据环境，按 `docs/Windows客户端互联剪贴板ROADMAP.md` 的 W2W-13 顺序完成邀请、确认码、首次配对，以及 A→B/B→A 自动同步测试。
2. 继续验证重复文本、256 KiB 超限、同步暂停、应用重启、系统唤醒、断网恢复、IP 变化、VPN/TUN 与防火墙；记录每项通过/失败证据。
3. 加入现有 HarmonyOS 手机和平板，验证 Windows + Windows + 手机 + 平板实时分发无重复、无串空间、无回环，再验证离线补齐与成员移除/旧密钥拒绝。
4. 若全部通过，更新 `docs/MANUAL_REGRESSION.md`、根 `README.md`、`desktop/README.md` 和 `DESKTOP_DEVELOPMENT_TODO.md`，最后勾选 W2W-13；版本号只能在这之后调整。
5. 再运行 `pnpm release:check`、发布安全检查和 `git diff --check`，然后生成最终发布 handoff。不要自动提交，除非用户明确要求。

## Blockers/Open Questions

- [ ] W2W-13 需要用户提供两台真实 Windows 设备，以及手机/平板 HarmonyOS 真机配合；单机自动化不能替代。
- [ ] 正式签名与上架包仍取决于用户本机证书和发布账号；仓库中不得保存这些材料。

### Deferred Items

- 版本号提升和正式安装包发布：Roadmap 明确要求 W2W-13 全部通过后再做。
- 公网中继、云同步、账号系统和后台 HarmonyOS 监听：均超出 EggClip v1 范围。

## Important Context

- 当前 `git status --short` 中本轮 15 个实现/文档文件显示为已暂存修改；这些是用户当前工作，不要 reset、checkout、取消暂存或覆盖。新 handoff 文件本身尚需按实际状态核查。
- W2W-12 已真实完成并通过自动门禁，不要重复拆分或向 Roadmap 添加子任务。下一轮直接从 W2W-13 开始。
- 最近一次完整 `pnpm release:check` 结果：Svelte check 0 错误/0 警告，前端 11 项测试通过，生产构建通过，`cargo fmt -- --check`、`cargo check` 通过，Rust 178 项测试通过，协议 fixture 校验通过，发布安全检查通过。
- 最后一次独立安全复查输出：`protocol fixtures ok`；扫描 359 个仓库路径、0 个发布包，检查通过；`git diff --check` 仅提示未来可能发生 LF→CRLF 转换，没有空白错误。
- `harmony/build-profile.json5` 当前是安全的脱敏共享版本。本机忽略文件 `harmony/build-profile.local*.json5` 保存了开发者本地配置；不要读取、打印、提交或在 handoff 中记录其内容。
- 真机 Harmony 构建前可运行 `./scripts/sanitize-harmony-build-profile.ps1 -Restore`；构建结束后必须运行 `./scripts/sanitize-harmony-build-profile.ps1` 再次脱敏，然后运行发布安全门禁。
- 不能把完整邀请、剪贴板正文、密钥、摘要、原始帧或签名材料放进普通日志、文档、错误消息或测试快照。

### Assumptions Made

- 用户已经认可当前 Windows↔HarmonyOS 基础共享剪贴板行为，本阶段只补齐 Windows↔Windows 产品化和最终回归。
- W2W-13 的人工结果由用户反馈后再勾选；未获得明确通过反馈的项目保持未完成。
- Windows 是桌面 v1 唯一承诺平台，HarmonyOS 目标仍为手机和平板前台连接。

### Potential Gotchas

- `git status --short` 的 `M ` 表示修改已在暂存区，不是普通未暂存 ` M`；保护现有索引状态。
- 不要直接输出 `harmony/build-profile.json5` 的历史 diff；旧版本可能含本机签名信息。可以运行 `git diff --check`、`git diff --stat` 和安全脚本。
- `PairingInvitationSummary` 在 Rust 内仍可临时构造 `invitation` 供后端处理，但该字段使用 `skip_serializing`；不要重新加入 TypeScript DTO。
- QR SVG 必然编码邀请内容，因此它只用于当前邀请展示；不得写入数据库、日志或历史文件。
- `ITEM_BATCH` 只补历史，W2W-13 验收时若它覆盖系统剪贴板就是阻断缺陷，不能解释为正常行为。
- POC 在线状态不能作为可信会话在线证据；设备列表应显示正式可信设备状态。

## Environment State

### Tools/Services Used

- Node/pnpm：运行桌面 Svelte 检查、测试、构建和 `release:check`。
- Rust/Cargo：运行格式检查、编译检查和 178 项测试。
- PowerShell 5：运行 `scripts/release-safety-check.ps1` 与 Harmony 配置脱敏脚本。
- Python：运行 `session-handoff` 生成与验证脚本；Windows 下设置 `PYTHONUTF8=1` 避免 GBK 解码问题。

### Active Processes

- 本交接没有启动需继续维护的 dev server、Tauri 进程或监控任务。

### Environment Variables

- `PYTHONUTF8`：handoff Python 脚本使用。
- `JAVA_HOME`、`DEVECO_SDK_HOME`：仅在后续 Harmony CLI 构建时需要，值按 `AGENTS.md` 配置，handoff 不记录敏感值。

## Related Resources

- [Windows 客户端互联 Roadmap](../../docs/Windows客户端互联剪贴板ROADMAP.md)
- [Windows 客户端互联实现方案](../../docs/Windows客户端互联剪贴板实现方案.md)
- [手动回归清单](../../docs/MANUAL_REGRESSION.md)
- [发布与回滚清单](../../docs/RELEASE.md)
- [桌面端开发说明](../../desktop/README.md)
- [桌面端 TODO](../../DESKTOP_DEVELOPMENT_TODO.md)
- [项目开发约定](../../AGENTS.md)

---

**Security Reminder**: 继续工作和正式发布前运行 `scripts/release-safety-check.ps1`，不得在输出或文档中暴露本机签名配置、邀请秘密、密钥或剪贴板正文。
