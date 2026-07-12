# Handoff: EggClip 1.0.1、桌面开机启动与 HarmonyOS 平板布局

## Session Metadata

- Created: 2026-07-12 16:07:12
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Upstream before version bump: `origin/main` at `6ee3479`
- Current committed HEAD: `6ee3479 feat: 添加开机自动启动设置，支持Windows系统托盘启动`
- Session duration: 约 3 小时

### Recent Commits

- `6ee3479` feat: 添加开机自动启动设置，支持Windows系统托盘启动
- `5a489e4` refactor: 重构页面布局为响应式Grid，更新签名配置
- `91e79af` docs: 添加UI精简与版本统一handoff文档
- `bc8484c` feat: 升级至1.0.0并新增关于页面
- `2e71eb5` fix: 添加authenticated字段以准确判断认证连接状态

## Handoff Chain

- **Continues from**: [2026-07-12-130045-eggclip-ui-refinement-about-v1.md](./2026-07-12-130045-eggclip-ui-refinement-about-v1.md)
- **Supersedes as current status**: the previous handoff for current version, tablet layout, autostart, validation, and release artifact facts.

## Current State Summary

EggClip 的共享剪贴板、配对、可信重连、加密实时同步、离线补同步和历史管理主链路保持可用。上一份 handoff 后完成了 HarmonyOS phone/tablet 响应式 Grid 布局和桌面“设置 → 常规 → 开机自动启动”能力，并制作了应用市场介绍文案与三张 1920×1080 横版宣传图。本轮将桌面端和 HarmonyOS 端语义版本统一升级到 `1.0.1`：HarmonyOS `versionCode` 同步递增到 `10001`，`buildVersion` 递增到 `2`。桌面完整检查、6 项 Vitest、130 项 Rust 测试、HarmonyOS 单测/HAP 构建以及 release metadata 校验全部通过。当前未提交变更只有五个版本文件和本 handoff；1.0.1 正式发布包尚未生成或签名。

## Codebase Understanding

## Architecture Overview

- `desktop/` 是 Tauri 2 + Svelte 5 + Rust Windows 托盘应用。系统能力通过 `src/lib/api/` 类型化封装，UI 状态通过 `src/lib/stores/` 编排。
- 桌面 autostart 使用 Tauri 官方插件，OS 启动项是事实来源，不写入 EggClip SQLite 设置 JSON。
- `harmony/` 使用 ArkUI 响应式 `GridRow/GridCol`：窄窗口维持手机单列，中等/大窗口切换双栏，不按设备型号硬编码平板模式。
- `protocol/` 没有在本轮修改；版本 `1.0.1` 是应用发行版本，协议版本仍为 v1。
- `docs/UI_REFINEMENT_ROADMAP.md` 阶段 1 至 3 已完成，阶段 4 仍需要完整人工验收后才能勾选。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/package.json` | 桌面前端和关于页版本来源 | 当前未提交值 `1.0.1` |
| `desktop/src-tauri/Cargo.toml` | Rust crate 版本 | 当前未提交值 `1.0.1` |
| `desktop/src-tauri/Cargo.lock` | Rust 锁文件中的 EggClip 包版本 | Cargo 已同步为 `1.0.1` |
| `desktop/src-tauri/tauri.conf.json` | NSIS 安装包版本 | 当前未提交值 `1.0.1` |
| `harmony/AppScope/app.json5` | HarmonyOS 发行版本 | `versionName=1.0.1`, `versionCode=10001`, `buildVersion=2` |
| `desktop/src/lib/api/autostart.ts` | Tauri autostart 类型化 API | 封装 `isEnabled/enable/disable` |
| `desktop/src/lib/stores/autostart.ts` | Windows 启动项 UI 状态 | 读取系统事实、切换后复核、失败回退 |
| `desktop/src/routes/+page.svelte` | 桌面设置入口 | 常规页显示开机自动启动开关 |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | HarmonyOS 首页 | 平板宽屏为 5:7 剪贴板/历史双栏 |
| `harmony/entry/src/main/ets/pages/DevicesPage.ets` | HarmonyOS 设备页 | 宽屏为可信设备与添加/诊断双栏 |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | HarmonyOS 设置页 | 宽屏按策略与隐私/安全分成两栏 |
| `harmony/entry/src/main/ets/pages/PairingPage.ets` | HarmonyOS 配对表单 | 最大宽度 600vp，避免平板横向过度拉伸 |
| `scripts/verify-release-metadata.ps1` | 双端版本与发布配置一致性门禁 | 已通过 EggClip `1.0.1` |
| `docs/UI_REFINEMENT_ROADMAP.md` | UI 完成标准 | 阶段 4 仍未完整验收 |

## Key Patterns Discovered

- 应用版本升级必须同步桌面 `package.json`、`Cargo.toml`、`Cargo.lock`、`tauri.conf.json` 和 HarmonyOS `versionName`。
- HarmonyOS 每个新发行构建还需保证 `versionCode` 与 `buildVersion` 单调递增；1.0.1 使用 `10001` 和 `2`。
- 关于页面从 `package.json` 读取版本，因此本轮版本升级会自动显示 1.0.1，不需要修改组件文案。
- 开机启动设置不属于 `AppSettings` 数据库模型。页面加载时读取 Windows 真实状态，用户切换后再次调用 `isEnabled()` 复核。
- 平板适配基于窗口断点，而不是 `deviceType === tablet`，从而兼容横竖屏和应用分屏。
- 用户要求 TODO 保持固定：不再新增过程性任务；满足整个现有条目后才打勾。

## Work Completed

## Tasks Finished

- [x] HarmonyOS 首页改为手机单列、中宽 1:1、平板宽屏 5:7 响应式布局。
- [x] HarmonyOS 设备页改为可信设备与添加/连接问题响应式双栏。
- [x] HarmonyOS 设置页改为同步/历史与外观/隐私/安全响应式双栏。
- [x] HarmonyOS 配对表单限制最大宽度 600vp。
- [x] 桌面设置常规页新增开机自动启动开关。
- [x] 新增类型化 autostart API/store、成功路径测试、README 和手动回归项。
- [x] 制作应用介绍、一句话简介和三张 1920×1080 横版宣传图。
- [x] 双端版本升级为 1.0.1，HarmonyOS 构建号同步递增。
- [x] 完成双端自动化测试、构建和版本一致性校验。

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/package.json` | `1.0.0` → `1.0.1` | 桌面前端和关于页版本 |
| `desktop/src-tauri/Cargo.toml` | `1.0.0` → `1.0.1` | Rust crate 版本 |
| `desktop/src-tauri/Cargo.lock` | EggClip 包 `1.0.0` → `1.0.1` | 与 Cargo manifest 一致 |
| `desktop/src-tauri/tauri.conf.json` | `1.0.0` → `1.0.1` | NSIS 安装包版本 |
| `harmony/AppScope/app.json5` | 语义版本和构建序号递增 | HarmonyOS 1.0.1 发布元数据 |

前两项功能已分别提交到 `5a489e4` 和 `6ee3479`；具体文件变更见 recent commits。

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Harmony 1.0.1 使用 versionCode 10001 | 保持 10000、改为 10100、递增到 10001 | 发布构建号必须单调递增，延续已有 10000 编码 |
| Harmony buildVersion 改为 2 | 保持 1、随版本递增 | 明确区分 1.0.0 与 1.0.1 构建 |
| autostart 不自动静默开启 | 首次运行强制开启、读取系统状态由用户控制 | 避免升级时未经用户同意修改 Windows 登录启动项 |
| 平板继续使用底部悬浮 HdsTabs | 平板改侧栏、保留底部导航 | 仅三个一级页面，保持用户已确认的官方悬浮页签体验 |
| 不勾选 UI Roadmap 阶段 4 | 自动化通过即完成、等待完整人工验收 | 平板真机、大字体、屏幕阅读和完整状态截图仍未全部完成 |

## Pending Work

## Immediate Next Steps

1. 检查本轮五个版本文件与 handoff 后提交；不要把构建产物、签名材料或本机绝对证书路径带入提交。
2. 使用 `pnpm release:bundle` 重新生成 1.0.1 NSIS 内部验收包；旧 1.0.0/0.1.0 安装器均已过时。
3. 使用发布脚本重新生成 1.0.1 HarmonyOS release HAP，并确认包内 `versionName=1.0.1`, `versionCode=10001`。
4. 在 Windows 手动开启/关闭“开机自动启动”，重新登录验证仅进入托盘且关闭后不再启动。
5. 在 HarmonyOS phone/tablet 或平板模拟器检查横屏、竖屏和分屏布局；完成 UI Roadmap 阶段 4 的截图、焦点、大字体和屏幕阅读验收。
6. 完成双端 2 小时稳定运行、正式签名、覆盖升级、卸载和回滚后，再勾选剩余 TODO。

## Blockers/Open Questions

- [ ] Windows 正式发布仍需要合法 Authenticode 证书或外部签名服务。
- [ ] HarmonyOS 正式发布仍需要用户合法的应用签名能力；签名材料不得写入仓库或 handoff。
- [ ] 当前 HDC 返回 `[Empty]`，没有连接的手机、平板或模拟器，无法在本轮安装 1.0.1 HAP 做运行时截图。
- [ ] Windows 登录重启会改变用户当前桌面会话，开机启动开关尚未由自动化替用户修改或做重新登录验收。
- [ ] `5a489e4` 包含 `harmony/build-profile.json5` 变更。下一轮发布前应使用安全检查确认共享配置不含本机签名材料，但不要在聊天或 handoff 中打印配置内容。

## Deferred Items

- 自动更新、云同步、公网中继、遥测和崩溃上报不属于 v1。
- 正式商店上传等待证书、真机回归和用户确认。
- TODO 与 UI Roadmap 不增加过程性小项，只按已有条目收口。

## Context for Resuming Agent

## Important Context

- 当前 committed HEAD 是 `6ee3479`，与 `origin/main` 一致；1.0.1 版本文件尚未提交。
- 当前工作树应包含五个版本文件和本 handoff。除此之外若出现新差异，先确认是否属于用户改动。
- 当前统一应用版本是 `1.0.1`，不是上一份 handoff 中的 `1.0.0`。
- 所有旧版本 NSIS/HAP 都不能作为 1.0.1 正式发布包，需要重建并重新检查签名。
- 本轮没有修改协议版本、数据库 schema、加密算法或同步业务逻辑。
- 桌面 autostart 的 OS 状态才是真实状态；不要再往 `AppSettings` JSON 添加重复字段。
- HarmonyOS 平板布局已完成代码层响应式重排，但没有连接设备做真实平板视觉验收。
- `harmony/build-profile.json5` 受签名安全约束。不要展示其中任何 material、路径或密码字段，也不要擅自回退用户已提交的配置。
- 用户坚持按既有 TODO 推进：完成一个完整条目才打勾，不追加开发过程。

## Assumptions Made

- Windows 10/11 是桌面 v1 唯一正式支持平台。
- HarmonyOS 目标仍为 SDK 6.1 phone/tablet。
- `versionCode=10001` 和 `buildVersion=2` 是 1.0.1 的发布构建序号，后续版本必须继续递增。
- 开机启动默认不因升级而强制开启，由用户在设置中明确选择。
- 平板适配断点由 ArkUI `GridRow` 根据当前窗口宽度自动决定。

## Potential Gotchas

- 桌面关于页版本来自 `desktop/package.json`；不要额外硬编码另一个版本字符串。
- Cargo.lock 中只能修改 `name = "eggclip"` 对应的版本，其他版本号属于第三方依赖。
- `pnpm tauri dev` 的 Vite 地址保持 `127.0.0.1`，VPN/TUN 环境下不要改回 `localhost`。
- autostart 真机测试会修改 Windows 登录启动项；自动化不要未经用户确认替用户开启或关闭。
- HarmonyOS 编译仍会输出已有 may-throw 和 Pasteboard 权限静态 warning；构建成功且未出现新增 error。
- 平板双栏只在窗口宽度达到中/大断点时出现；平板分屏缩窄后回到单列是预期行为。
- 应用市场宣传图是模型辅助合成图，正式上架前应人工检查 UI 字样、设备指纹等可见信息是否需要替换。
- Windows 上运行 handoff 脚本必须设置 `PYTHONUTF8=1`。

## Environment State

## Tools/Services Used

- Desktop: pnpm 11.3.0, SvelteKit/Vite, Rust/Cargo, Tauri 2.
- HarmonyOS: DevEco Studio JBR, SDK 6.1, Hvigor.
- Version gate: `scripts/verify-release-metadata.ps1`.
- Handoff tooling: `C:\Users\caozhipeng\.agents\skills\session-handoff\scripts\` with `PYTHONUTF8=1`.

## Active Processes

- No EggClip desktop process was visible at final check.
- No Vite listener was visible on `127.0.0.1:1420` at final check.
- HDC reported `[Empty]`; no HarmonyOS target is connected.

## Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`
- Signing-related secret values are intentionally not recorded.

## Validation Evidence

- Desktop `pnpm check`: 0 errors, 0 warnings.
- Desktop `pnpm test`: 6 tests passed.
- Desktop `pnpm build`: passed.
- Rust `cargo fmt -- --check`: passed.
- Rust `cargo check`: passed.
- Rust `cargo test`: 130 tests passed.
- HarmonyOS `hvigorw test --no-daemon`: passed.
- HarmonyOS `hvigorw assembleHap --no-daemon`: passed.
- `scripts/verify-release-metadata.ps1`: passed for EggClip `1.0.1`.
- `git diff --check`: passed.

## External Release Assets

The following user-requested assets are outside the repository and were present at handoff creation:

- `C:\Users\caozhipeng\Desktop\截图\EggClip应用介绍.md`
- `C:\Users\caozhipeng\Desktop\截图\应用介绍截图\01-电脑复制手机即见-1920x1080.png`
- `C:\Users\caozhipeng\Desktop\截图\应用介绍截图\02-扫码配对可信重连-1920x1080.png`
- `C:\Users\caozhipeng\Desktop\截图\应用介绍截图\03-历史由你掌控-1920x1080.png`

## Related Resources

- [AGENTS.md](../../AGENTS.md)
- [UI refinement roadmap](../../docs/UI_REFINEMENT_ROADMAP.md)
- [Desktop TODO](../../DESKTOP_DEVELOPMENT_TODO.md)
- [HarmonyOS TODO](../../HARMONY_DEVELOPMENT_TODO.md)
- [Desktop README](../../desktop/README.md)
- [Release guide](../../docs/RELEASE.md)
- [Manual regression checklist](../../docs/MANUAL_REGRESSION.md)
- [Release metadata validator](../../scripts/verify-release-metadata.ps1)
- [Previous handoff](./2026-07-12-130045-eggclip-ui-refinement-about-v1.md)

---

**Security Reminder**: This handoff intentionally excludes signing material, passwords, invitation secrets, encryption keys, clipboard contents, and complete protocol frames. Validate before finalizing.
