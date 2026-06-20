# Handoff: EggClip 两端 Shell 分层基线完成

## Session Metadata
- Created: 2026-06-20 21:49:20
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 本轮约 1 小时，主要完成两端 Shell 层分层、空服务骨架、验证和计划文档同步。

### Recent Commits (for context)
  - f4bac6a feat: 建立桌面端和鸿蒙端的Shell层基线，包含状态管理、UI组件与空服务骨架
  - 6c17e4a fix: 将桌面端开发地址从localhost改为127.0.0.1以修复VPN下连接问题
  - 4e24147 feat: 建立两端工程基线和主题空壳
  - 74d9bb1 feat: 初始化 EggClip 项目，包含开发约定、方案和 HarmonyOS 工程
  - 35b524b Initial commit

## Handoff Chain

- **Continues from**: [2026-06-20-182235-eggclip-desktop-localhost-fix.md](./2026-06-20-182235-eggclip-desktop-localhost-fix.md)
  - Previous title: EggClip 两端工程基线与桌面端 127.0.0.1 dev 修复
- **Supersedes**: None. This handoff extends the previous one after the Shell-layer baseline commit.

## Current State Summary

EggClip 当前已完成两端工程基线和 Shell 层分层。桌面端已从硬编码首页拆出 TypeScript `types/api/stores/components` 基线，HarmonyOS 端已建立 `models/store/services/data/components/utils` 目标目录和空服务骨架，首页改为消费初始 store 状态。相关修改已进入最新提交 `f4bac6a`，远端 `origin/main` 也指向该提交。当前工作树除本 handoff 文件外无业务代码改动。

## Important Context

EggClip v1 的边界仍然固定：纯局域网、无账号/无云/无公网中继、只同步 `text/plain`，单条明文最大 256 KiB；Windows 桌面端未来可以自动写入在线实时剪贴板事件，HarmonyOS 端必须通过真实 `PasteButton` 触发读取，并且收到远端内容后只能由用户点击复制到系统剪贴板。当前刚完成的是架构承载层，不是剪贴板、网络或加密协议实现。历史提交 `74d9bb1` 曾包含 Harmony 签名配置风险；当前 `harmony/build-profile.json5` 已脱敏，但用户仍需轮换相关签名材料并决定是否清理远端历史。不要在任何文档、日志或测试快照中输出签名 material、真实剪贴板正文、邀请秘密、密钥或完整网络帧。

## Immediate Next Steps

1. 桌面端进入 D1：先实现 Rust `clipboard/` 模块骨架、文本大小限制和回环抑制的纯逻辑测试，再接 Win32 `AddClipboardFormatListener` 真机事件循环。
2. HarmonyOS 进入 H1：先确认 `module.json5` 中 mDNS/WebSocket POC 所需最小网络权限，再做前台 mDNS 搜索、手动 IP WebSocket 和真实 `PasteButton` POC。
3. 将 POC 结果记录到 `docs/`，特别是 Windows 防火墙、VPN、访客网络/AP 隔离、Harmony 真机权限和前后台生命周期限制。
4. 若要提交本 handoff，需要用户明确要求；默认保持未暂存状态，不自动提交。

## Architecture Overview

仓库是单仓双端结构：`desktop/` 为 Tauri 2 + SvelteKit/Svelte 5 + Rust，`harmony/` 为 DevEco Stage Model ArkTS 工程，`protocol/` 后续用于共享 schema 和跨语言测试向量。桌面端页面现在只组合组件与 store，后续系统剪贴板、SQLite、mDNS、WebSocket、配对和加密应留在 Rust 后端模块中，由 `src/lib/api/` 做 Tauri command/event 的类型化封装。HarmonyOS 页面现在只组合 ArkUI UI 和 store，后续 RDB、mDNS、WebSocket、Pasteboard、HUKS/CryptoFramework 应分别进入 `data/` 和 `services/`，不要堆回 `HomePage.ets` 或 `Index.ets`。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| AGENTS.md | 仓库级开发约定和产品/安全不变量 | 后续开发优先遵守 |
| DESKTOP_DEVELOPMENT_TODO.md | 桌面端阶段计划 | D0 已更新为 Shell 分层完成，下一步是 D1 POC |
| HARMONY_DEVELOPMENT_TODO.md | HarmonyOS 阶段计划 | H0 已更新为目标目录完成，下一步是 H1 POC |
| desktop/src/lib/api/shell.ts | 桌面端 UI 初始快照 API 边界 | 后续接 Tauri command/event 时从这里扩展 |
| desktop/src/lib/stores/shell.ts | 桌面端 shell store | 首页订阅该 store，不直接写业务状态 |
| desktop/src/lib/types/shell.ts | 桌面端连接、设备、剪贴板预览和历史类型 | 后续前后端 DTO 应与这里对齐 |
| desktop/src/lib/components/common/StatusDot.svelte | 桌面端状态点组件 | 统一 online/offline/connecting/authFailed/paused 状态展示 |
| desktop/src/routes/+page.svelte | 桌面端主面板组合页 | 现在负责页面组合，不承载服务逻辑 |
| harmony/entry/src/main/ets/models/ShellModels.ets | Harmony Shell 状态模型 | 后续 store/service/UI 的共同类型入口 |
| harmony/entry/src/main/ets/store/HomeStore.ets | Harmony 首页初始状态 | HomePage 从这里读取初始状态 |
| harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets | Harmony 剪贴板服务占位 | 已包含文本非空和 256 KiB 估算校验，后续接真实 PasteButton/Pasteboard |
| harmony/entry/src/main/ets/services/discovery/MdnsDiscoveryService.ets | Harmony mDNS 服务占位 | H1 会接 `@ohos.net.mdns` |
| harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets | Harmony WebSocket 服务占位 | H1 会接 NetworkKit WebSocket |
| harmony/entry/src/main/ets/pages/HomePage.ets | Harmony 首页 | 已从硬编码状态改为使用 `HomeStore` 和 `StatusDot` |

## Key Patterns Discovered

- 桌面端页面不直接持有业务事实；使用 `ShellSnapshot`、`shellSnapshot` store 和小组件组合 UI。
- HarmonyOS 端页面只组合页面级 UI；平台能力通过 `services/` 占位，数据持久化通过 `data/` 预留。
- `Index.ets` 必须保持轻量入口，当前只包一层 `HomePage()`，不要重新堆积业务。
- 开发服务器已固定到 `127.0.0.1:1420`，VPN 环境不要退回 `localhost`。
- Harmony HAP 构建在脱敏共享配置下会出现“未找到 signingConfig”的警告，这是当前预期状态，不代表业务构建失败。
- 文档中的安全术语可能命中简单文本扫描；判断时要区分“设计术语”和真实密钥/签名 material。

## Work Completed

## Tasks Finished

- [x] 桌面端新增 `desktop/src/lib/types/shell.ts`，定义连接状态、设备摘要、剪贴板预览、历史摘要和 Shell 快照。
- [x] 桌面端新增 `desktop/src/lib/api/shell.ts` 和 `desktop/src/lib/stores/shell.ts`，建立 API/store 分层入口。
- [x] 桌面端新增 `ClipboardCard`、`HistoryList`、`StatusCard`、`StatusDot`、`DeviceChips` 组件。
- [x] 桌面端 `+page.svelte` 改为组合组件并订阅 store，移除页面内硬编码设备数组。
- [x] 桌面端测试扩展为覆盖初始 shell 状态、默认历史上限和文本大小边界。
- [x] HarmonyOS 新增 `harmony/entry/src/main/ets/models/ShellModels.ets`、`harmony/entry/src/main/ets/store/HomeStore.ets` 和 `harmony/entry/src/main/ets/components/common/StatusDot.ets`。
- [x] HarmonyOS 新增 `services/discovery`、`services/transport`、`services/clipboard`、`services/sync` 空服务骨架。
- [x] HarmonyOS 新增 `data/db`、`data/migrations`、`data/repositories` 目录占位，以及 `PairingPage`、`DevicesPage`、`SettingsPage` 空页面。
- [x] HarmonyOS `HomePage.ets` 改为消费初始 shell 状态并复用 `StatusDot`。
- [x] 更新 `DESKTOP_DEVELOPMENT_TODO.md` 和 `HARMONY_DEVELOPMENT_TODO.md`，标记桌面 TS 分层和 Harmony 目标模块目录完成。
- [x] 完成桌面端和 HarmonyOS 构建/测试验证，并将结果写入本 handoff。

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| DESKTOP_DEVELOPMENT_TODO.md | D0 状态更新；勾选 TypeScript API/store/component 分层 | 计划文档与实际代码保持一致 |
| HARMONY_DEVELOPMENT_TODO.md | H0 状态更新；勾选目标模块目录和空入口 | 计划文档与实际代码保持一致 |
| desktop/src/app.css | 补充 connecting/auth-failed/paused 状态点样式 | 后续连接状态能有不同反馈 |
| desktop/src/lib/api/shell.ts | 新增初始 shell 快照工厂 | 建立 UI 与 Tauri 后端之间的 API 边界 |
| desktop/src/lib/stores/shell.ts | 新增 shell store 和在线设备数 derived store | 后续 UI 状态集中管理 |
| desktop/src/lib/types/shell.ts | 新增 Shell 相关类型 | 保持 TypeScript 严格类型 |
| desktop/src/lib/components/clipboard/ClipboardCard.svelte | 新增当前剪贴板卡片组件 | 从页面拆出剪贴板展示 |
| desktop/src/lib/components/clipboard/HistoryList.svelte | 新增历史空态组件 | 从页面拆出历史展示 |
| desktop/src/lib/components/common/StatusCard.svelte | 新增连接状态卡片 | 统一连接状态展示 |
| desktop/src/lib/components/common/StatusDot.svelte | 新增状态点组件 | 统一状态颜色与状态枚举 |
| desktop/src/lib/components/devices/DeviceChips.svelte | 新增设备 chips 组件 | 从页面拆出设备展示 |
| desktop/src/lib/shell.test.ts | 增加初始状态测试 | 固定 v1 默认边界和页面状态 |
| desktop/src/routes/+page.svelte | 重构为导入组件和 store | 页面只负责组合，不承载业务 |
| harmony/entry/src/main/ets/models/ShellModels.ets | 新增 Harmony Shell 状态模型 | 为 store、服务和页面提供共同类型 |
| harmony/entry/src/main/ets/store/HomeStore.ets | 新增首页初始状态工厂 | 页面状态集中管理 |
| harmony/entry/src/main/ets/components/common/StatusDot.ets | 新增 ArkUI 状态点组件 | 统一移动端连接状态展示 |
| harmony/entry/src/main/ets/pages/HomePage.ets | 接入 HomeStore 和 StatusDot | 页面不再直接写死所有状态 |
| harmony/entry/src/main/ets/pages/PairingPage.ets | 新增配对页面占位 | 后续 H4 配对页面入口 |
| harmony/entry/src/main/ets/pages/DevicesPage.ets | 新增设备页面占位 | 后续 H6 设备管理入口 |
| harmony/entry/src/main/ets/pages/SettingsPage.ets | 新增设置页面占位 | 后续 H6 设置入口 |
| harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets | 新增剪贴板桥接服务占位和文本大小校验 | H1 PasteButton/Pasteboard POC 前置边界 |
| harmony/entry/src/main/ets/services/discovery/MdnsDiscoveryService.ets | 新增 mDNS 服务占位 | H1 mDNS POC 前置边界 |
| harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets | 新增 WebSocket 服务占位 | H1 WebSocket POC 前置边界 |
| harmony/entry/src/main/ets/services/sync/SyncCoordinator.ets | 新增同步协调占位 | 后续 live/batch 分流入口 |
| harmony/entry/src/main/ets/utils/TextLimits.ets | 新增 256 KiB 文本限制常量 | Harmony 侧复用 v1 文本边界 |
| harmony/entry/src/main/ets/data/README.md | 说明 data 层职责 | 防止页面或组件直接访问 RDB |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| 先做 Shell 分层，不直接接剪贴板和网络 | 直接进入 D1/H1 POC、先做分层 | 两端页面仍处于空壳期，先建立分层能避免平台 API 代码堆进页面 |
| 桌面端初始状态通过 `createInitialShellSnapshot()` 提供 | 页面内常量、store 初始化工厂、后端 command 拉取 | 当前还没有 Rust 后端状态服务，使用 API 工厂能保留后续替换空间 |
| HarmonyOS 服务先做空骨架 | 立即导入 mDNS/WebSocket/Pasteboard API、只建目录、不写接口 | 真机 POC 前不写死可能错误的平台调用，同时给后续 H1 留明确入口 |
| HarmonyOS 文本大小校验先用 UTF-8 字节估算 | 暂不校验、使用字符数、服务层估算 | v1 边界是字节大小，先在服务层保留明确限制；后续可替换为更严格编码实现 |
| TODO 文档随代码同步更新 | 只写代码、不更新计划 | 后续代理要按阶段推进，计划状态必须准确 |

## Pending Work

## Blockers/Open Questions

- [ ] Harmony 签名历史风险仍未最终处理。当前共享配置已脱敏，但历史提交 `74d9bb1` 曾含签名配置风险；需要用户决定是否只轮换签名材料，还是进一步重写远端历史。
- [ ] Windows 剪贴板事件监听尚未实现；D1 需要 Win32 真机验证，模拟构建不能替代。
- [ ] HarmonyOS mDNS/WebSocket/PasteButton 尚未做真机 POC；H1 需要真实设备验证，模拟器不能替代。
- [ ] `protocol/` 目录、schema 和跨语言测试向量尚未创建；要等核心 POC 风险降低后再进入正式协议阶段。

## Deferred Items

- 桌面端 SQLite、系统凭据库、开机启动策略 UI 和正式设置页未做；原因是当前仍处于 D0/D1 交界，先验证剪贴板和网络核心风险。
- HarmonyOS RDB、HUKS/CryptoFramework、扫码配对和正式设置页未做；原因是 H1 先验证前台平台能力。
- 桌面端 `pnpm tauri dev` 在用户 VPN 开启状态下的交互确认仍建议用户本机再跑一次；前一轮只做过短启动验证。

## Context for Resuming Agent

## Assumptions Made

- 最新提交 `f4bac6a` 已被用户或外部流程提交并推送到 `origin/main`，当前业务代码工作树干净。
- 当前手头任务是继续按 TODO 开发，不需要自动创建分支、暂存、提交或推送。
- HarmonyOS POC 应采用普通三方应用可接受权限路径，不能依赖系统级静默读取剪贴板权限。
- Windows v1 只承诺 Windows 10/11，不需要为 macOS/Linux 添加未验证代码。

## Potential Gotchas

- 不要因为 `harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets` 有校验函数，就误认为 PasteButton/Pasteboard POC 已完成；它只是服务边界占位。
- 不要把 `MdnsDiscoveryService.ets` 和 `WebSocketTransportService.ets` 的空方法当成可用实现；下一步必须接入真实 HarmonyOS API 并做生命周期清理。
- 桌面端 `shellSnapshot` 当前是静态初始状态；接 Tauri event 时要保持 Svelte 组件不直接访问 SQLite、剪贴板或 socket。
- `git status` 现在会显示本 handoff 文件未跟踪；这不是业务代码脏改。
- Harmony `assembleHap` 的 signingConfig 警告是当前脱敏配置的预期结果；不要为消除警告把本机签名 material 提交回仓库。
- 如果继续做 Win32 剪贴板监听，Rust 正常业务路径不要使用无上下文的 `unwrap()` 或 `expect()`。

## Environment State

## Tools/Services Used

- PowerShell in `D:\Develop\eggclip`。
- Node/pnpm for desktop SvelteKit checks, tests and build.
- Rust/Cargo for Tauri backend format/check/test.
- DevEco Studio JBR/Hvigor for HarmonyOS `test` and `assembleHap`。
- `session-handoff` skill scripts from `C:\Users\caozhipeng\.agents\skills\session-handoff`。

## Active Processes

- 没有需要下一代理接管的 dev server、watcher、Tauri app 或 Harmony 构建进程。
- 本 handoff 生成时没有启动长期后台服务。

## Environment Variables

- `TAURI_DEV_HOST`：仅远程调试时使用；普通桌面开发不需要设置。
- `JAVA_HOME`：HarmonyOS hvigor 命令需要指向 DevEco Studio JBR。
- `DEVECO_SDK_HOME`：HarmonyOS hvigor 命令需要指向 DevEco Studio SDK。
- `PYTHONUTF8`：Windows 下运行 handoff Python 脚本时设置为 `1`，避免中文内容编码问题。

## Related Resources

- AGENTS.md
- README.md
- DESKTOP_DEVELOPMENT_TODO.md
- HARMONY_DEVELOPMENT_TODO.md
- docs/EggClip最佳实现方案.md
- desktop/src/lib/api/shell.ts
- desktop/src/lib/stores/shell.ts
- desktop/src/lib/types/shell.ts
- desktop/src/routes/+page.svelte
- harmony/entry/src/main/ets/models/ShellModels.ets
- harmony/entry/src/main/ets/store/HomeStore.ets
- harmony/entry/src/main/ets/pages/HomePage.ets
- harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets
- .claude/handoffs/2026-06-20-182235-eggclip-desktop-localhost-fix.md

## Verification Snapshot

- `pnpm check` in `D:\Develop\eggclip\desktop`: passed.
- `pnpm test` in `D:\Develop\eggclip\desktop`: passed, 1 test file / 2 tests.
- `pnpm build` in `D:\Develop\eggclip\desktop`: passed.
- `cargo fmt -- --check` in `D:\Develop\eggclip\desktop\src-tauri`: passed.
- `cargo check` in `D:\Develop\eggclip\desktop\src-tauri`: passed.
- `cargo test` in `D:\Develop\eggclip\desktop\src-tauri`: passed, 3 Rust tests.
- `hvigorw test --no-daemon` in `D:\Develop\eggclip\harmony`: passed.
- `hvigorw assembleHap --no-daemon` in `D:\Develop\eggclip\harmony`: passed with expected warning about missing signingConfig.
- `harmony/build-profile.json5` current file was checked for signing material markers and remained sanitized.
- `git diff --check` passed during development with only line-ending conversion warnings.

## Current Git State

- Branch: `main`
- Upstream: `origin/main`
- HEAD: `f4bac6a feat: 建立桌面端和鸿蒙端的Shell层基线，包含状态管理、UI组件与空服务骨架`
- Status after generating this handoff:
  - `main...origin/main`
  - Untracked: `.claude/handoffs/2026-06-20-214920-eggclip-two-sides-layering.md`
  - No staged files.
  - No unstaged business-code modifications.

---

Security note: this handoff intentionally records only risk categories and file locations. It does not include signing material, certificate contents, private keys, token values, invitation secrets, real clipboard samples, plaintext network frames, or credential values.
