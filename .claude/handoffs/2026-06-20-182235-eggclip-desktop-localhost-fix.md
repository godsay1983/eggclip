# Handoff: EggClip 两端工程基线与桌面端 127.0.0.1 dev 修复

## Session Metadata
- Created: 2026-06-20 18:22:35
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 本轮约 30 分钟；此前会话已完成两端工程基线、计划文档和初始主题空壳，并已提交到 `main`。

### Recent Commits (for context)
  - 4e24147 feat: 建立两端工程基线和主题空壳
  - 74d9bb1 feat: 初始化 EggClip 项目，包含开发约定、方案和 HarmonyOS 工程
  - 35b524b Initial commit

## Handoff Chain

- **Continues from**: None (fresh start)
- **Supersedes**: None

## Current State Summary

EggClip 仓库已经具备桌面端 Tauri 2 + Svelte 5 工程、HarmonyOS DevEco 工程、项目约定、两端 TODO 和最佳实现方案。用户反馈在开启 VPN 时桌面端 `pnpm tauri dev` 连接不上 `localhost`，已参照 EggDone 的经验将桌面端开发地址改为 IPv4 loopback `127.0.0.1`。当前工作树只有本轮两个未提交文件：`desktop/src-tauri/tauri.conf.json` 和 `desktop/vite.config.js`；未暂存、未提交、未推送。

## Important Context

EggClip（蛋定 Clip）是纯局域网剪贴板同步工具，v1 边界固定：Windows 桌面端托盘常驻、局域网发现连接和自动同步；HarmonyOS 端仅前台发现连接，接收内容需用户点击复制，发送内容必须通过系统 `PasteButton` 授权；只同步 `text/plain`，单条明文最大 256 KiB，不引入账号、云端、S3、公网中继或遥测。当前 `main` 的最新提交是 `4e24147`，它包含两端工程基线。历史提交 `74d9bb1` 中的 `harmony/build-profile.json5` 曾包含 Harmony 签名配置模式；当前工作树扫描未发现相关敏感模式，但需要用户轮换相关签名材料，并决定是否重写远端历史。不要在聊天、文档、日志或测试快照中输出 Harmony 签名 material 内容。

## Immediate Next Steps

1. 在用户当前 VPN 开启状态下，于 `D:\Develop\eggclip\desktop` 运行 `pnpm tauri dev`，确认 Tauri 窗口能从 `http://127.0.0.1:1420` 加载前端。
2. 若验证通过，将 `desktop/src-tauri/tauri.conf.json` 与 `desktop/vite.config.js` 作为一个小提交候选；提交前至少运行 `pnpm check`，风险允许时补跑 `pnpm test`、`pnpm build`、`cargo fmt -- --check`、`cargo check`、`cargo test`。
3. 与用户确认 Harmony 签名历史处理策略：至少轮换本机签名材料；如要清除远端历史，需要单独授权执行历史改写与 force push 流程。
4. 继续按 `DESKTOP_DEVELOPMENT_TODO.md` 和 `HARMONY_DEVELOPMENT_TODO.md` 推进，不跨阶段堆叠协议、配对、剪贴板和存储功能。

## Codebase Understanding

## Architecture Overview

仓库根目录 `D:\Develop\eggclip` 同时承载桌面端、HarmonyOS 端、文档和后续协议目录。桌面端位于 `desktop/`，使用 Tauri 2 作为壳层和系统集成层，SvelteKit/Svelte 5 作为轻量面板 UI。HarmonyOS 工程根目录就是 `harmony/`，不要再创建 `harmony/EggClip/` 嵌套目录。共享协议后续应落在 `protocol/`，Rust 和 ArkTS 各自实现同一协议与测试向量，不共享运行时代码。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| AGENTS.md | 仓库级开发约定、产品边界、安全边界和验证要求 | 后续所有开发必须优先遵守 |
| docs/EggClip最佳实现方案.md | 产品和架构决策来源 | 需求冲突时优先级高于 TODO |
| DESKTOP_DEVELOPMENT_TODO.md | 桌面端阶段计划 | 后续 Windows/Tauri/Rust/Svelte 开发按阶段推进 |
| HARMONY_DEVELOPMENT_TODO.md | HarmonyOS 端阶段计划 | 后续 ArkUI、PasteButton、发现连接和同步按阶段推进 |
| desktop/src-tauri/tauri.conf.json | Tauri 桌面配置 | 本轮将 dev URL 从 `localhost` 改为 `127.0.0.1` |
| desktop/vite.config.js | Vite 开发服务器配置 | 本轮将默认 host 绑定到 `127.0.0.1` |
| harmony/build-profile.json5 | Harmony 构建配置 | 当前文件已脱敏，但历史提交风险仍需处理 |

## Key Patterns Discovered

- Windows/VPN 环境下避免依赖 `localhost` 解析，桌面端 dev server 应显式使用 `127.0.0.1`。
- Vite 的 `TAURI_DEV_HOST` 只保留给远程设备调试；普通桌面开发默认不应启用额外的 HMR `1421` 端口。
- Tauri `beforeDevCommand` 会自行启动 `pnpm dev`。如果已有孤立 `vite dev` 占用 `1420`，`pnpm tauri dev` 会因为 `strictPort` 失败。
- 当前项目不允许自动提交、推送、创建分支或发布安装包，除非用户明确要求。
- Harmony 签名文件处理必须只记录风险和策略，不能泄露本机路径、证书、私钥或受保护字段内容。

## Work Completed

## Tasks Finished

- [x] 生成项目协作约定、桌面端 TODO、HarmonyOS TODO 和 README 基线。
- [x] 基于 EggClip 实现方案和 EggDone 风格建立桌面端 Tauri/Svelte 空壳。
- [x] 建立 HarmonyOS DevEco 工程主题空壳，Index 页面已轻量化。
- [x] 运行并通过桌面端前端、Rust 和 Harmony 构建校验；Harmony HAP 构建因共享配置脱敏而存在预期签名警告。
- [x] 修复 VPN 下 Tauri dev 连接 `localhost` 不稳定问题，将桌面端开发地址改为 `127.0.0.1`。
- [x] 短启动验证 `pnpm tauri dev --no-dev-server-wait --no-watch -v`，确认 Vite 输出 `http://127.0.0.1:1420/`，Tauri 运行到 `target\debug\eggclip.exe`。
- [x] 结束本次验证产生的 `node.exe` 与 `eggclip.exe` 进程，避免留下端口占用。

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| desktop/src-tauri/tauri.conf.json | `build.devUrl` 从 `http://localhost:1420` 改为 `http://127.0.0.1:1420` | 避免 VPN、hosts 或 IPv6/IPv4 解析导致 Tauri 无法加载本地前端 |
| desktop/vite.config.js | 新增 `remoteDevHost`，默认 `host` 为 `127.0.0.1`；仅设置 `TAURI_DEV_HOST` 时启用远程 HMR 配置 | 普通桌面开发只绑定 IPv4 loopback，同时保留远程调试能力 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| 桌面端 dev URL 固定为 `127.0.0.1` | `localhost`、`127.0.0.1`、`0.0.0.0` | 用户开启 VPN 后 `localhost` 连接不稳定；`127.0.0.1` 与 EggDone 经验一致且暴露面更小 |
| Vite 默认 host 绑定 `127.0.0.1` | 默认 false、本机 loopback、全接口监听 | Tauri 只需要本机访问；全接口监听对当前桌面开发没有必要 |
| HMR `1421` 仅在远程调试时使用 | 永远启用、永远关闭、按 `TAURI_DEV_HOST` 启用 | 避免普通 `pnpm tauri dev` 额外占用端口，同时不破坏 Tauri 远程调试模板 |
| 不提交本轮修复 | 立即提交、只落盘修改 | 用户只要求生成 handoff，且项目规则要求未经明确要求不自动提交 |

## Pending Work

## Blockers/Open Questions

- [ ] Harmony 签名历史风险：当前工作树扫描干净，但历史提交 `74d9bb1` 中存在签名配置模式；需要用户决定是否只轮换签名材料，还是进一步重写远端历史。
- [ ] 桌面端 `pnpm tauri dev` 需要在用户实际 VPN 环境下手动确认窗口加载与托盘交互；短启动只验证了服务地址和进程启动。
- [ ] 后续协议、配对、安全存储和剪贴板监听尚未实现；继续开发前应严格按 TODO 阶段推进。

## Deferred Items

- 真实托盘点击、隐藏面板和 Windows 剪贴板行为的完整手动验收暂未执行；原因是本轮目标是修复 dev 连接地址并生成 handoff。
- HarmonyOS 真机上的 mDNS、WebSocket、PasteButton、Pasteboard、HUKS 验收暂未执行；原因是当前仍处于工程空壳和计划准备阶段。
- 协议目录 `protocol/`、schema 和跨语言测试向量尚未开始；原因是应在两端基础工程稳定后进入协议阶段。

## Context for Resuming Agent

## Assumptions Made

- 用户的 VPN 改变了 `localhost` 解析或本地回环连接行为，改成 `127.0.0.1` 能解决 Tauri dev 加载失败。
- `TAURI_DEV_HOST` 仍可能在远程调试 HarmonyOS 设备时需要，因此没有删除该配置分支。
- 当前 `main` 与 `origin/main` 对齐；本轮未提交文件是有意保留给用户或下一轮代理处理。
- Harmony 当前共享 `build-profile.json5` 保持脱敏状态，具体本机签名配置由用户在本地环境自行管理。

## Potential Gotchas

- 如果 `pnpm tauri dev` 报 `Port 1420 is already in use`，先查是否有旧 `vite dev` 进程占用，不要盲目改端口。
- 如果普通开发没有设置 `TAURI_DEV_HOST`，不应看到 Vite 单独监听 `1421`；看到时检查环境变量或旧进程。
- `git diff --check` 可能提示 LF/CRLF 转换 warning，这不是本轮功能问题；不要顺手做全仓格式化。
- 不要把 Harmony 签名 material、证书路径、受保护字段、真实剪贴板内容或邀请密钥写入文档、日志或测试。
- 桌面端收到在线实时事件可以自动写系统剪贴板，但离线补齐历史不能覆盖当前系统剪贴板；这是产品不变量。

## Environment State

## Tools/Services Used

- PowerShell in `D:\Develop\eggclip`。
- Node/pnpm for desktop frontend and Tauri dev commands.
- Rust/Cargo through Tauri desktop project.
- DevEco Studio JBR/Hvigor for HarmonyOS validation in earlier setup.
- `session-handoff` skill scripts from `C:\Users\caozhipeng\.agents\skills\session-handoff`。

## Active Processes

- 本轮 handoff 生成前的短启动验证已清理相关 `node.exe`、`eggclip.exe` 进程。
- 生成 handoff 时未留下需要下一代理接管的 dev server、watcher 或后台构建进程。

## Environment Variables

- `TAURI_DEV_HOST`：仅远程调试时使用；普通桌面开发不需要设置。
- `JAVA_HOME`：HarmonyOS hvigor 验证时需要指向 DevEco Studio JBR。
- `DEVECO_SDK_HOME`：HarmonyOS hvigor 验证时需要指向 DevEco Studio SDK。
- `PYTHONUTF8`：Windows 下运行 handoff Python 脚本时设置为 `1`，避免中文路径或中文内容编码问题。

## Related Resources

- AGENTS.md
- README.md
- DESKTOP_DEVELOPMENT_TODO.md
- HARMONY_DEVELOPMENT_TODO.md
- docs/EggClip最佳实现方案.md
- desktop/README.md
- desktop/package.json
- desktop/vite.config.js
- desktop/src-tauri/tauri.conf.json
- harmony/build-profile.json5

## Verification Snapshot

- `pnpm check` in `D:\Develop\eggclip\desktop`: passed, `svelte-check found 0 errors and 0 warnings`.
- `pnpm tauri dev --no-dev-server-wait --no-watch -v`: short-start passed; Vite reported `Local: http://127.0.0.1:1420/`; Tauri ran `target\debug\eggclip.exe`.
- Current tree sensitive-pattern scan for Harmony signing markers: clean.
- Historical check: `74d9bb1:harmony/build-profile.json5` contains signing configuration patterns; material values were not printed or copied into this handoff.
- `git diff --check -- desktop/vite.config.js desktop/src-tauri/tauri.conf.json`: passed, only line-ending conversion warnings were reported.

## Current Git State

- Branch: `main`
- Upstream: `origin/main`
- Status: `main...origin/main`
- Unstaged modified files:
  - `desktop/src-tauri/tauri.conf.json`
  - `desktop/vite.config.js`
- Staged files: none.
- New handoff file created:
  - `.claude/handoffs/2026-06-20-182235-eggclip-desktop-localhost-fix.md`

---

Security note: this handoff intentionally records only the existence of Harmony signing history risk and does not include any signing material, key path, certificate body, secret value, clipboard sample, invitation secret, token, or network frame payload.
