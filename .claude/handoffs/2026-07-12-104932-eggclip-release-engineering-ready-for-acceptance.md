# Handoff: EggClip 发布工程完成，等待双端人工验收与正式签名

## Session Metadata

- Created: 2026-07-12 10:49:32
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: 约 2 小时
- Current commit: `9cd2183 feat: 添加发布流程：NSIS内部验收包与HarmonyOS检查包构建脚本及文档`

### Recent Commits (for context)

- `9cd2183` feat: 添加发布流程：NSIS内部验收包与HarmonyOS检查包构建脚本及文档
- `a46996d` chore: 集成发布安全检查与隐私文档，重构连接状态逻辑
- `b1b072b` feat: 添加连接体验卡片和重试连接，重构桌面端传输与托盘状态
- `fdf4bbd` feat: 完善托盘状态与断线补同步功能
- `49420c9` feat: 实现设备重命名与移除功能，并显示配对连接状态

## Handoff Chain

- **Continues from**: [2026-07-11-170252-eggclip-sync-backfill-in-progress.md](./2026-07-11-170252-eggclip-sync-backfill-in-progress.md)
- **Supersedes as current status**: the previous handoff and all older implementation-progress handoffs; consult them only for historical debugging details.

## Current State Summary

EggClip v1 的核心业务链路已完成：桌面端与 HarmonyOS 可通过邀请完成认证配对、自动可信重连、应用层加密实时同步、断线补同步、ACK、加密历史、设备和空间管理。最近一轮完成了可靠发送/UI 状态自动化覆盖、隐私与局域网排障说明、发布秘密检查，以及 Windows NSIS 和 HarmonyOS release HAP 的内部构建流程。当前 `main` 工作树除本 handoff 外干净。两个内部产物均成功构建并通过安全检查，但都未使用正式发布证书；剩余工作是用户主导的双端真机回归、2 小时稳定运行、正式签名、覆盖升级和卸载验收。

## Codebase Understanding

## Architecture Overview

- `desktop/` 是 Tauri 2 + Svelte 5 + Rust 的 Windows 托盘应用。Svelte 只通过类型化 API/store 调用 Rust，不直接访问 SQLite、剪贴板或 socket。
- `harmony/` 是 HarmonyOS SDK 6.1 ArkTS/ArkUI 工程。页面组合 UI，store 编排状态，service 处理网络/加密/同步，data 处理 RDB。
- `protocol/` 是 Rust 与 ArkTS 共同消费的协议 schema 和测试向量；运行时代码不共享。
- mDNS 只提供地址候选；身份信任来自配对、设备身份签名和认证会话。
- 实时 `ITEM_LIVE` 可按策略更新桌面系统剪贴板；离线 `ITEM_BATCH` 只补历史，绝不覆盖当前剪贴板。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `DESKTOP_DEVELOPMENT_TODO.md` | 桌面端唯一剩余任务清单 | 不新增任务；仅在完整验收后勾选 |
| `HARMONY_DEVELOPMENT_TODO.md` | HarmonyOS 唯一剩余任务清单 | 不新增任务；仅在完整验收后勾选 |
| `docs/RELEASE.md` | 双端版本、签名、升级、卸载与回滚清单 | 下一阶段的主操作文档 |
| `docs/PRIVACY.md` | v1 数据处理和用户控制说明 | 发布权限/隐私事实来源 |
| `docs/LAN_TROUBLESHOOTING.md` | VPN、TUN、防火墙和 AP 隔离排障 | 手动回归时使用 |
| `scripts/build-desktop-release.ps1` | 完整检查并生成 NSIS 内部包 | 正式证书配置前产物仅供内部验收 |
| `scripts/build-harmony-release.ps1` | 单测并生成 release 未签名 HAP | 正式包应由 DevEco/CI 注入签名 |
| `scripts/verify-release-metadata.ps1` | 校验两端版本、identifier、NSIS 与备份策略 | 每次版本调整必须通过 |
| `scripts/release-safety-check.ps1` | 扫描秘密、禁止产物和发布包调试文件 | 发布前必跑 |
| `desktop/src-tauri/tauri.conf.json` | NSIS、元数据、WebView2 与安装模式 | v1 只生成 Windows NSIS |
| `harmony/build-profile.json5` | 可提交的无签名共享构建配置 | 不能写入任何本机 signing material |
| `harmony/entry/src/main/resources/base/profile/backup_config.json` | HarmonyOS 数据备份策略 | 当前必须保持 `allowToBackupRestore: false` |

## Key Patterns Discovered

- TODO 已重新基线化；开发只能执行现有条目，完成后打勾，不能把过程性小任务继续追加到 TODO。
- 发布元数据四处保持一致：桌面 `package.json`、`Cargo.toml`、`tauri.conf.json` 与 HarmonyOS `versionName`；HarmonyOS 发布还要递增 `versionCode` 和 `buildVersion`。
- 共享 Harmony 构建配置永远无签名材料；本机签名配置被忽略，正式签名通过 DevEco Studio 本机配置或 CI secret 注入。
- HarmonyOS 数据备份关闭，因为 RDB 内 HUKS 引用无法脱离原设备安全存储独立恢复。
- Windows v1 使用 `currentUser` NSIS，不请求管理员权限；用户数据默认保留，避免卸载误删历史和凭据。

## Work Completed

### Tasks Finished

- [x] 完成桌面端完整自动化测试 TODO：clipboard、storage、protocol、crypto、sync、ConnectionManager 和 Svelte store。
- [x] 完成 HarmonyOS 自动化测试 TODO：sync、ConnectionManager、stores、首页 UI 状态与跨端协议向量。
- [x] 新增隐私说明、局域网排障说明和发布安全扫描，桌面对应 TODO 已勾选。
- [x] 桌面 bundle 限定为 NSIS，并补齐发布者、许可证、中英文、WebView2 和当前用户安装配置。
- [x] HarmonyOS release 内部构建脚本、权限说明、备份边界与升级/回滚说明完成。
- [x] 生成并检查 Windows NSIS 内部包和 HarmonyOS 未签名 HAP。

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src-tauri/tauri.conf.json` | 仅 NSIS、发布元数据、语言、图标、WebView2、currentUser | 与 Windows-only v1 边界一致 |
| `desktop/package.json` | 增加 `release:bundle` | 单命令生成内部验收安装器 |
| `desktop/README.md` | 增加 NSIS 内部包说明 | 给开发者明确入口 |
| `harmony/README.md` | 增加 release HAP 和签名边界 | 防止误把未签名包当正式包 |
| `harmony/entry/src/main/resources/base/profile/backup_config.json` | 关闭备份恢复 | 防止 RDB/HUKS 不一致恢复 |
| `docs/RELEASE.md` | 新增签名、升级、卸载和回滚清单 | 持久化发布流程 |
| `LICENSE` | 增加 MIT 许可证正文 | 与 Cargo/package 元数据一致 |
| `scripts/*.ps1` | 增加构建、版本和安全门禁 | 保证发布流程可重复 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| 桌面只生成 NSIS | `all`、MSI、NSIS | Windows v1 只需一个轻量安装器；避免 WiX/VBSCRIPT 额外依赖 |
| NSIS 使用 `currentUser` | per-machine、both、current-user | 托盘剪贴板工具无需管理员权限，降低安装摩擦 |
| 使用 WebView2 download bootstrapper | offline、fixed runtime、skip、download | Windows 10/11 通常已有 WebView2；保持安装器约 4 MiB |
| 内部包允许未签名但明确告警 | 阻止所有未签名构建、允许内部包 | 自动化可验证构建；正式发布仍必须受信任签名 |
| HarmonyOS 关闭应用数据备份 | 开启、关闭 | HUKS 密钥不随普通 RDB 备份迁移，开启会产生不可恢复引用 |
| 暂不勾选两个发布 TODO | 按代码完成勾选、等待完整验收 | TODO 同时要求正式签名及升级/卸载实测，当前尚未满足 |

## Pending Work

## Immediate Next Steps

1. 用户按现有验收清单完成桌面 Windows 10/11、DPI、多显示器、防火墙、Wi-Fi/睡眠切换和快速连续复制回归；全部通过后勾选桌面 TODO 第 56 项。
2. 用户在 HarmonyOS 手机/平板真机完成网络切换、前后台、锁屏、异常配对、PasteButton、Emoji、256 KiB 边界和连续发送；全部通过后勾选 Harmony TODO 第 63 项。
3. 双端连续运行 2 小时，记录无崩溃、无断线未恢复、无回环风暴；通过后勾选桌面 TODO 第 57 项。
4. 配置合法正式证书，验证 Windows Authenticode 与 HarmonyOS 正式签名，并执行覆盖升级、卸载和回滚清单；通过后分别勾选桌面第 61 项、Harmony 第 64 项。

### Blockers/Open Questions

- [ ] Windows 代码签名需要用户合法证书或外部签名服务；当前 NSIS 的 Authenticode 状态是 `NotSigned`。
- [ ] HarmonyOS 正式签名需要用户 DevEco/发布证书；共享配置生成的是 `entry-default-unsigned.hap`。
- [ ] Windows 10、多显示器、HarmonyOS 平板等环境是否齐备由用户确认；模拟器不能替代网络、PasteButton 和 HUKS 真机验收。

### Deferred Items

- 正式对外发布、商店上传和证书注入：等待用户证书与人工验收。
- 自动更新、云同步、公网中继、遥测和崩溃上报：不属于 v1，禁止顺手加入。
- HarmonyOS release 混淆：当前保持关闭，避免在缺少完整混淆真机回归时破坏协议序列化、RDB 与 ArkUI 导出名称；这不是 v1 发布阻塞项。

## Context for Resuming Agent

## Important Context

- 当前不是继续增加核心功能的阶段。共享剪贴板主链路已经可用，下一阶段是人工质量验收和正式签名发布。
- 用户明确要求每轮按两个 TODO 文件推进，每次完成一个现有任务后打勾，不再新增过程任务。
- 不要把内部未签名产物描述成正式发布包。最近成功生成的本地产物位于：
  - `desktop/src-tauri/target/release/bundle/nsis/EggClip_0.1.0_x64-setup.exe`
  - `harmony/entry/build/default/outputs/default/entry-default-unsigned.hap`
- 上述 build/target 目录被忽略，新的 agent 不能假设换机或清理后产物仍存在；必要时用构建脚本重建。
- `harmony/build-profile.local.json5` 是被忽略的本机配置。不得读取、展示、复制或提交其中的签名内容。
- 普通日志、handoff 和测试输出不得出现剪贴板正文、邀请秘密、密钥、完整摘要或签名材料。

## Assumptions Made

- v1 只正式支持 Windows 10/11 桌面与 HarmonyOS 6.1 phone/tablet。
- 当前统一应用版本是 `0.1.0`；下一次发布需要同步所有版本面。
- 正式发布由用户提供代码签名/应用签名能力；仓库不托管任何证书或密码。
- 卸载默认保留用户数据和凭据；完全清理必须由用户主动选择。

## Potential Gotchas

- Windows PowerShell 5.1 默认代码页会破坏 UTF-8 中文 JSON；发布脚本读取配置时必须显式 `-Encoding UTF8`。
- 在 Windows 上运行 session-handoff Python 脚本前设置 `PYTHONUTF8=1`，否则 GBK 可能导致文档生成或校验失败。
- `release-safety-check.ps1 -PackagePaths` 的相对路径以仓库根为基准；从命令行检查多个包时建议分别调用，避免 PowerShell `-File` 数组参数解析歧义。
- Harmony 构建会输出既有 ArkTS “may throw” 和 Pasteboard 权限静态警告；当前测试和真机 PasteButton 流程可用，但不要把 warning 当成正式签名成功。
- Tauri release 首次全量编译约需数分钟；不要因长时间无输出重复启动第二个构建。
- 当前 Git branch 是 `main`，最近发布变更已提交到 `9cd2183`；生成 handoff 前工作树仅有本 handoff 未跟踪。

## Environment State

### Tools/Services Used

- Node.js + pnpm；桌面命令：`pnpm release:check`、`pnpm release:bundle`。
- Rust stable 1.85+；Tauri 2 / Cargo。
- DevEco Studio JBR、HarmonyOS SDK 6.1、Hvigor。
- 发布门禁：`scripts/verify-release-metadata.ps1`、`scripts/release-safety-check.ps1`。
- Handoff 工具：`C:\Users\caozhipeng\.agents\skills\session-handoff\scripts\`。

### Active Processes

- 无需要接管的后台构建、服务或监控进程。
- 桌面 `tauri dev` 和 HarmonyOS 应用真机实例是否仍运行应由用户现场确认。

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`
- 正式签名相关变量/secret 名称应由用户 CI 或签名服务定义，不写入仓库或 handoff。

## Validation Evidence

- Desktop: `pnpm release:check` passed.
- Desktop: 5 Vitest tests and 130 Rust tests passed.
- Desktop: NSIS installer generated; size about 4.13 MiB; security scan passed; Authenticode not signed.
- HarmonyOS: Hvigor unit tests and release HAP build passed.
- HarmonyOS: unsigned HAP generated; size about 1.11 MiB; security scan passed.
- Release metadata check passed for version `0.1.0`.
- Release safety check passed for 294 repository paths and both generated packages when checked separately.
- `git diff --check` passed before handoff creation.

## Related Resources

- [AGENTS.md](../../AGENTS.md)
- [DESKTOP_DEVELOPMENT_TODO.md](../../DESKTOP_DEVELOPMENT_TODO.md)
- [HARMONY_DEVELOPMENT_TODO.md](../../HARMONY_DEVELOPMENT_TODO.md)
- [README.md](../../README.md)
- [docs/RELEASE.md](../../docs/RELEASE.md)
- [docs/PRIVACY.md](../../docs/PRIVACY.md)
- [docs/LAN_TROUBLESHOOTING.md](../../docs/LAN_TROUBLESHOOTING.md)
- [docs/EggClip最佳实现方案.md](../../docs/EggClip最佳实现方案.md)
- [protocol/README.md](../../protocol/README.md)

---

**Security Reminder**: Before finalizing, run `validate_handoff.py` and reject any document that contains signing material, secrets, clipboard samples, or a score below 70.
