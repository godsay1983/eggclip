# Handoff: EggClip 桌面端 1.0.2 与认证文本实时预览

## Session Metadata

- Created: 2026-07-12 16:48:59
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Current committed HEAD: `90ab299 feat: 支持认证剪贴板文本的自动接收与预览`
- Session duration: 约 20 分钟

### Recent Commits

- `90ab299` feat: 支持认证剪贴板文本的自动接收与预览
- `eb44fbd` fix(build): 修改签名配置为默认签名
- `964dbd2` chore: 升级版本至1.0.1并更新关于页面
- `6ee3479` feat: 添加开机自动启动设置，支持Windows系统托盘启动
- `5a489e4` refactor: 重构页面布局为响应式Grid，更新签名配置

## Handoff Chain

- **Continues from**: [2026-07-12-160712-eggclip-1-0-1-autostart-tablet-ready.md](./2026-07-12-160712-eggclip-1-0-1-autostart-tablet-ready.md)
- **Supersedes as current status**: the previous handoff for the latest desktop version and authenticated Harmony-to-Windows preview behavior.

## Current State Summary

EggClip 的双端认证同步主链路可用。用户验证 HarmonyOS 点击系统 PasteButton 后，Windows 已能直接粘贴收到的文本，但桌面面板此前必须点击“读取本机剪贴板”才刷新。该缺陷已在提交 `90ab299` 修复：Svelte API/store 监听 Rust 发出的 `transport://authenticated-clipboard-text`，立即更新首页预览并刷新历史，同时继续使用既有远端写入回环抑制，避免再次发送回 HarmonyOS。本轮按用户要求仅把桌面端发行版本从 `1.0.1` 升级到 `1.0.2`；HarmonyOS 保持 `1.0.1`。桌面前端检查、7 项 Vitest、生产构建、Rust 格式检查、编译和 130 项测试全部通过。四个桌面版本文件与本 handoff 尚未提交。

## Codebase Understanding

## Architecture Overview

- `desktop/src-tauri/src/transport/mod.rs` 在认证 `ITEM_LIVE` 通过策略、持久化和剪贴板写入后发出 `transport://authenticated-clipboard-text`。
- `desktop/src/lib/api/shell.ts` 将 Tauri 事件转换为类型化 `ClipboardPreview`，避免 Svelte 组件直接处理底层事件格式。
- `desktop/src/lib/stores/shell.ts` 统一更新首页当前文本、连接状态和历史摘要；远端事件只更新状态，不调用发送命令。
- `desktop/src-tauri/src/clipboard/mod.rs` 负责 Windows 远端写入抑制；认证事件刷新 UI 不经过剪贴板监视器，因此不会破坏回环控制。
- 桌面关于页从 `desktop/package.json` 注入版本，版本升级后自动显示 `1.0.2`。
- 当前发布脚本仍采用双端统一版本策略，`scripts/verify-release-metadata.ps1` 会拒绝桌面 `1.0.2` 与 HarmonyOS `1.0.1` 的组合。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/package.json` | 前端包及关于页版本来源 | 当前未提交值为 `1.0.2` |
| `desktop/src-tauri/Cargo.toml` | Rust crate 版本 | 当前未提交值为 `1.0.2` |
| `desktop/src-tauri/Cargo.lock` | 锁文件中的 EggClip 包版本 | 当前未提交值为 `1.0.2` |
| `desktop/src-tauri/tauri.conf.json` | Tauri/NSIS 包版本 | 当前未提交值为 `1.0.2` |
| `harmony/AppScope/app.json5` | HarmonyOS 发行版本 | 保持 `versionName=1.0.1` |
| `desktop/src/lib/api/shell.ts` | Tauri command/event 类型化适配 | 已监听认证远端文本事件 |
| `desktop/src/lib/stores/shell.ts` | 桌面 UI 状态编排 | 收到认证文本后立即刷新预览和历史 |
| `desktop/src/lib/shell.test.ts` | Svelte store/API 回归测试 | 覆盖认证 Harmony 文本到预览的映射 |
| `desktop/README.md` | 桌面运行与同步行为说明 | 已说明无需手动读取即可刷新 |
| `scripts/verify-release-metadata.ps1` | 双端统一版本门禁 | 当前因双端版本不同而按设计失败 |

## Key Patterns Discovered

- 桌面版本必须同步修改 `package.json`、`Cargo.toml`、`Cargo.lock` 中 `name = "eggclip"` 的 package 条目和 `tauri.conf.json`。
- 正式认证远端文本与未认证 POC 文本使用不同事件；不能把认证事件接入 POC 自动复制路径。
- 收到远端文本后的 UI 刷新必须直接消费认证事件，不能依赖 Windows 剪贴板监听回显，因为回显会被安全回环机制抑制。
- 首页预览更新不能调用任何发送 API；远端写入只应更新 UI/历史，防止形成双端同步回环。
- 用户要求 TODO 保持固定，只勾选已有完整任务，不增加过程性子项。

## Work Completed

## Tasks Finished

- [x] 验证 HarmonyOS 到 Windows 的认证 `ITEM_LIVE`、系统剪贴板写入和直接粘贴均正常。
- [x] 修复桌面面板未监听认证远端文本事件的问题。
- [x] 收到 HarmonyOS 文本后立即更新桌面首页预览并刷新历史。
- [x] 保留远端剪贴板写入抑制，未引入同步回环。
- [x] 增加认证 Harmony 文本预览映射回归测试。
- [x] 将桌面端四个版本入口从 `1.0.1` 升级为 `1.0.2`。
- [x] 完成桌面前端、构建与 Rust 自动化验证。

## Files Modified

当前未提交文件如下；认证预览修复已包含在提交 `90ab299` 中。

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/package.json` | `1.0.1` → `1.0.2` | 前端和关于页显示新版本 |
| `desktop/src-tauri/Cargo.toml` | `1.0.1` → `1.0.2` | Rust crate 版本一致 |
| `desktop/src-tauri/Cargo.lock` | EggClip package `1.0.1` → `1.0.2` | 与 Cargo manifest 一致 |
| `desktop/src-tauri/tauri.conf.json` | `1.0.1` → `1.0.2` | Tauri/NSIS 安装包版本一致 |
| `.claude/handoffs/2026-07-12-164859-eggclip-desktop-1-0-2-authenticated-preview.md` | 新交接文档 | 保存当前版本、验证和发布门禁状态 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| 本轮只升级桌面到 1.0.2 | 双端一起升级、仅桌面升级 | 用户明确要求“桌面端版本修改为1.0.2” |
| 不修改统一发布门禁 | 放宽为双端独立版本、保持门禁 | 改变发布版本策略超出本轮请求，应由用户明确决定 |
| UI 直接监听认证事件 | 依赖剪贴板监听回显、轮询读取、直接监听认证事件 | 回显被回环抑制是正确安全行为，认证事件是可靠状态来源 |
| 不改变 Rust 收发链路 | 重写后端写入、仅补前端事件消费 | Windows 已能直接粘贴，证明后端链路正常 |

## Pending Work

## Immediate Next Steps

1. 决定发行版本策略：若要运行现有统一发布脚本，应将 HarmonyOS 同步升级到 `1.0.2` 并递增构建号；若要允许双端独立发版，应先明确修改发布门禁和发布文档。
2. 在 Windows 运行 `pnpm tauri dev`，保持 HarmonyOS 可信连接，点击 PasteButton 后确认桌面首页和历史无需手动读取即可立即刷新，并确认 HarmonyOS 不会收到回环文本。
3. 人工验收通过后提交四个桌面版本文件与本 handoff；不要提交构建产物或签名材料。
4. 版本策略确定且门禁通过后，再生成并签名桌面 `1.0.2` NSIS 发布包。

## Blockers/Open Questions

- [ ] 桌面 `1.0.2` 与 HarmonyOS `1.0.1` 不满足当前双端统一版本门禁，`scripts/verify-release-metadata.ps1` 会报版本未对齐。
- [ ] 桌面认证预览修复已通过自动化，但仍需用户使用真实 HarmonyOS 设备做最终 UI 实时刷新验收。
- [ ] Windows 正式发布仍需要合法 Authenticode 证书或外部签名服务。
- [ ] HarmonyOS 签名配置属于敏感本机配置，不得在交接、日志或聊天中展示。

## Deferred Items

- 未擅自升级 HarmonyOS 到 `1.0.2`，因为用户本轮只指定桌面端。
- 未修改双端统一版本门禁，等待用户决定统一发版还是独立发版。
- 自动更新、云同步、公网中继、遥测和崩溃上报继续不属于 v1。

## Context for Resuming Agent

## Important Context

- 当前 committed HEAD 是 `90ab299`，认证远端文本预览修复已经提交，不在工作树差异中。
- 当前工作树应只有四个桌面版本文件和本 handoff；若出现其他差异，先确认是否为用户新增改动。
- 桌面当前目标版本是 `1.0.2`，HarmonyOS 仍是 `1.0.1`；这是用户本轮明确指定范围，不是遗漏。
- 桌面自身所有自动化验证均通过，但统一发布元数据门禁因双端版本不同而失败，当前不能直接使用 `scripts/build-desktop-release.ps1` 生成包。
- HarmonyOS 到 Windows 的真实剪贴板同步在修复前就已正常；`90ab299` 只修复桌面窗口没有即时刷新预览和历史的问题。
- 回环抑制不能删除。远端写入不触发 `clipboard://local-text` 是预期安全行为，前端应依赖 `transport://authenticated-clipboard-text`。
- 本轮没有修改协议版本、数据库 schema、加密算法、HarmonyOS 代码或同步网络格式。
- 不读取或展示 `harmony/build-profile.json5` 中的签名字段。

## Assumptions Made

- Windows 10/11 仍是桌面 v1 唯一正式支持平台。
- 应用版本 `1.0.2` 不改变共享协议 v1。
- 用户有意让桌面补丁版本先于 HarmonyOS，而不是遗漏“双端”字样。
- 关于页继续从 `desktop/package.json` 读取版本，不需要硬编码文本。

## Potential Gotchas

- 运行 `scripts/verify-release-metadata.ps1` 会失败，原因是它明确要求桌面和 HarmonyOS 版本一致；不要误判为桌面四个版本入口没有同步。
- `scripts/build-desktop-release.ps1` 会先调用该统一门禁，因此在版本策略解决前也会停止。
- Cargo.lock 只能更新 EggClip 自身 package 条目，不要批量替换第三方依赖版本。
- `pnpm tauri dev` 的 Vite 地址保持 `127.0.0.1`，VPN/TUN 环境下不要改回 `localhost`。
- 自动接收关闭时，桌面不应展示新远端实时预览；这是设置策略，不是事件监听故障。
- Windows 上运行 handoff 脚本需设置 `PYTHONUTF8=1`，避免 GBK 解码失败。

## Environment State

## Tools/Services Used

- Desktop: pnpm 11.3.0, SvelteKit/Vite, Rust/Cargo, Tauri 2.
- Version inspection: PowerShell, `rg`, Git.
- Handoff tooling: `C:\Users\caozhipeng\.agents\skills\session-handoff\scripts\` with `PYTHONUTF8=1`.

## Active Processes

- 本轮未启动 `pnpm tauri dev`。
- 未启动新的 Vite、EggClip 或 HarmonyOS 构建服务。
- 自动化命令均已结束。

## Environment Variables

- `PYTHONUTF8`
- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- 任何签名密码、证书材料和密钥值均未记录。

## Validation Evidence

- Desktop `pnpm check`: 0 errors, 0 warnings.
- Desktop `pnpm test`: 7 tests passed.
- Desktop `pnpm build`: passed.
- Rust `cargo fmt -- --check`: passed.
- Rust `cargo check`: passed; crate compiled as `eggclip v1.0.2`.
- Rust `cargo test`: 130 tests passed.
- `git diff --check`: pending final handoff validation run.
- `scripts/verify-release-metadata.ps1`: expected failure because desktop is `1.0.2` while HarmonyOS remains `1.0.1`.
- HarmonyOS tests were not rerun because no HarmonyOS file changed in this session.

## Related Resources

- [AGENTS.md](../../AGENTS.md)
- [Desktop README](../../desktop/README.md)
- [Desktop TODO](../../DESKTOP_DEVELOPMENT_TODO.md)
- [HarmonyOS TODO](../../HARMONY_DEVELOPMENT_TODO.md)
- [Release guide](../../docs/RELEASE.md)
- [Manual regression checklist](../../docs/MANUAL_REGRESSION.md)
- [Release metadata validator](../../scripts/verify-release-metadata.ps1)
- [Previous handoff](./2026-07-12-160712-eggclip-1-0-1-autostart-tablet-ready.md)

---

**Security Reminder**: This handoff intentionally excludes signing material, passwords, invitation secrets, encryption keys, clipboard contents, and complete protocol frames.
