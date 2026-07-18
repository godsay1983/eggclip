# Handoff: EggClip 双端 1.0.5 对齐，待 W2W-13 真机验收

## Session Metadata

- Created: 2026-07-18 12:30:58
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: 约 30 分钟

### Recent Commits

- `acde637 feat: 添加 W2W-12 交接文档，记录 Windows 客户端互联状态与安全检查`
- `d4f8dcf feat: 增强配对邀请安全性，添加剪贴板运行时和发布安全检查`
- `2a621cf feat: 重新设计设备配对界面，添加图标与视觉细节`
- `4855edb feat: 实现桌面端加入配对对话框，支持候选地址选择与错误分类`
- `df1d7c4 feat: 区分协调端与成员端角色，支持成员端离开空间`

## Handoff Chain

- **Continues from**: [2026-07-17-202504-eggclip-w2w12-automation-ready-w2w13-acceptance.md](./2026-07-17-202504-eggclip-w2w12-automation-ready-w2w13-acceptance.md)
- **Supersedes**: 上一份 handoff 的版本状态；W2W-01 至 W2W-12 的详细实现与安全背景仍以其为准。

## Current State Summary

桌面端此前为 `1.0.4`，HarmonyOS 为 `1.0.3`，不符合仓库统一版本门禁。本轮将桌面端和 HarmonyOS 统一提升到 `1.0.5`：桌面四个版本面已同步，HarmonyOS 更新为 `versionName 1.0.5`、`versionCode 10005`、`buildVersion 2`。版本一致性、安全扫描、协议 fixture、Svelte 类型检查和 Rust 编译检查均通过。版本改动尚未提交。Windows 互联 Roadmap 状态不变：W2W-01 至 W2W-12 已完成，下一项仍是 W2W-13 双 Windows 和混合设备真机验收。

## Architecture Overview

- 桌面发行版本有四个需要保持一致的版本面：`desktop/package.json`、`desktop/src-tauri/Cargo.toml`、`desktop/src-tauri/Cargo.lock` 中 `eggclip` package，以及 `desktop/src-tauri/tauri.conf.json`。
- HarmonyOS 发行版本位于 `harmony/AppScope/app.json5`，包括用户可见的 `versionName`、递增的 `versionCode` 和构建序号 `buildVersion`。
- `scripts/verify-release-metadata.ps1` 会校验桌面三个主要元数据版本与 HarmonyOS `versionName` 一致，并检查应用标识、NSIS 目标和 Harmony 备份安全策略。
- `scripts/release-safety-check.ps1` 负责协议 fixture 与敏感信息发布门禁；版本提升不能绕过该检查。

## Critical Files

| File | Purpose | Current state |
|---|---|---|
| `desktop/package.json` | 前端包及桌面版本来源 | `1.0.5` |
| `desktop/src-tauri/Cargo.toml` | Rust package 版本 | `1.0.5` |
| `desktop/src-tauri/Cargo.lock` | 锁定的 `eggclip` package 版本 | `1.0.5` |
| `desktop/src-tauri/tauri.conf.json` | Tauri 应用及安装包版本 | `1.0.5` |
| `harmony/AppScope/app.json5` | HarmonyOS 上架版本元数据 | `1.0.5 / 10005 / 2` |
| `scripts/verify-release-metadata.ps1` | 双端版本一致性门禁 | 已通过 |
| `docs/Windows客户端互联剪贴板ROADMAP.md` | Windows 互联固定任务与验收标准 | W2W-13 未完成 |

## Key Patterns Discovered

- “提升两端版本号”应选择一个高于两端现有值的统一补丁版本，不能分别递增后继续保持不一致。
- Cargo 版本提升必须同时更新 `Cargo.toml` 和 Cargo.lock 中名称为 `eggclip` 的 package 记录，不能批量替换其他依赖版本。
- HarmonyOS 的 `versionCode` 必须单调递增；本次使用与 `1.0.5` 对应的 `10005`。`buildVersion` 也按发布清单要求从 `1` 增加到 `2`。
- Harmony 签名材料不属于版本改动范围；不要读取、输出或提交本机签名配置。

## Work Completed

### Tasks Finished

- [x] 核对桌面端与 HarmonyOS 当前版本面。
- [x] 将桌面端所有发行版本面统一提升到 `1.0.5`。
- [x] 将 HarmonyOS 提升到 `versionName 1.0.5`、`versionCode 10005`、`buildVersion 2`。
- [x] 运行双端发布元数据一致性检查。
- [x] 运行协议 fixture 和发布安全检查。
- [x] 运行 Svelte 类型检查与 Rust 编译检查。
- [x] 运行 `git diff --check`。

## Files Modified

| File | Changes | Rationale |
|---|---|---|
| `desktop/package.json` | `1.0.4` → `1.0.5` | 更新前端和桌面包版本 |
| `desktop/src-tauri/Cargo.toml` | `1.0.4` → `1.0.5` | 更新 Rust crate 版本 |
| `desktop/src-tauri/Cargo.lock` | `eggclip 1.0.4` → `1.0.5` | 与 Cargo manifest 保持一致 |
| `desktop/src-tauri/tauri.conf.json` | `1.0.4` → `1.0.5` | 更新 Tauri 应用/安装包版本 |
| `harmony/AppScope/app.json5` | `1.0.3/10003/1` → `1.0.5/10005/2` | 与桌面端对齐并递增上架构建元数据 |

## Decisions Made

| Decision | Options considered | Rationale |
|---|---|---|
| 双端统一到 `1.0.5` | 分别升为桌面 1.0.5/Harmony 1.0.4；全部统一 1.0.4；全部统一 1.0.5 | `1.0.5` 高于两个当前版本且满足统一版本门禁，不会造成任一平台版本倒退 |
| Harmony `versionCode` 使用 `10005` | 仅加一为 10004；与语义版本对应为 10005 | 保持既有 `1.0.x ↔ 1000x` 规则，便于发布审查和后续维护 |
| `buildVersion` 增加为 `2` | 继续保持 1；递增为 2 | `docs/RELEASE.md` 要求每次发布同时递增 `versionCode` 和 `buildVersion` |

## Pending Work

版本提升工作已经完成。产品 Roadmap 唯一剩余任务是 W2W-13；在用户完成真机测试前不得勾选，也不得提前声明 Windows 互联最终验收完成。

## Immediate Next Steps

1. 使用两台真实 Windows 干净数据完成邀请、确认码、首次配对，以及 A→B、B→A 自动同步验收。
2. 按 W2W-13 验证重复文本、超限文本、同步暂停、重启、唤醒、断网恢复、IP 变化、VPN/TUN 和防火墙场景。
3. 加入 HarmonyOS 手机和平板，验证四端实时分发、离线补齐、成员移除、旧密钥拒绝，以及无重复、无串空间、无回环。
4. 用户确认全部通过后，更新 `docs/MANUAL_REGRESSION.md`、根 `README.md`、`desktop/README.md`、`DESKTOP_DEVELOPMENT_TODO.md` 并勾选 W2W-13。
5. 正式打包前执行完整 `pnpm release:check` 和相应 HarmonyOS 真机构建/回归；本轮只执行了与元数据变更成比例的检查，没有生成安装包或 HAP。

## Blockers/Open Questions

- [ ] W2W-13 需要两台 Windows 以及 HarmonyOS 手机/平板真机，由用户执行和反馈测试结果。
- [ ] 正式签名与上架包仍依赖用户本机证书和发布账号，仓库及 handoff 不得保存相关内容。

## Deferred Items

- 正式 Windows NSIS 和 HarmonyOS HAP 打包：等 W2W-13 通过后执行。
- W2W-13 文档收尾：等真实设备结果确定后同步，当前不提前勾选。

## Important Context

- 当前分支为 `main`，版本提升产生 5 个未提交、未暂存修改；不要 reset、checkout 或覆盖这些用户工作。
- 当前统一发行版本是 `1.0.5`，HarmonyOS 数字版本为 `versionCode 10005`、`buildVersion 2`。不要把 HarmonyOS 改回 `1.0.4`，否则会再次与桌面端和发布门禁冲突。
- 本轮验证结果：`verify-release-metadata.ps1` 通过并报告 EggClip `1.0.5`；协议 fixture 通过；发布安全检查扫描 360 个仓库路径、0 个发布包并通过；Svelte check 为 0 错误/0 警告；`cargo check` 成功编译 `eggclip v1.0.5`；`git diff --check` 仅有 LF→CRLF 提示，没有空白错误。
- W2W-12 的详细架构、安全实现、178 项 Rust 测试和 11 项前端测试结果记录在上一份 handoff。本轮没有修改功能代码，也没有重跑完整测试套件。
- 共享 `harmony/build-profile.json5` 应保持脱敏；本机签名恢复/净化流程见 `docs/RELEASE.md`，绝不能输出本机签名文件内容或历史 diff。

## Assumptions Made

- 用户的“提升两端版本号”表示发布版本统一递增，而不是让两个平台继续维持不同版本。
- `1.0.5` 是当前功能里程碑的新补丁版本；没有引入协议破坏性变更，因此不需要提升次版本。
- W2W-13 仍由用户在真实设备上验收，自动化不能替代。

## Potential Gotchas

- `rg` 整个 Cargo.lock 会显示大量依赖版本；核验 EggClip 时必须定位 `name = "eggclip"` 对应记录，不能替换其他 `1.0.4` 字符串。
- HarmonyOS 旧审核文档中出现的 `1.0.2` 是历史审核批次描述，不应随本次版本提升机械替换。
- 桌面 About 页从传入版本显示，不含需要手工替换的硬编码 `1.0.4`；HarmonyOS 用户可见版本来自应用元数据。
- `git diff --check` 的 LF→CRLF 是 Windows 工作区换行提醒，不是验证失败。
- 不要在未完成 W2W-13 时再次随意提升版本；Roadmap 要求最终回归后再做正式发布收尾。

## Environment State

### Tools/Services Used

- PowerShell：版本扫描、元数据检查、安全检查和 Git 状态检查。
- pnpm 11.3.0：`pnpm check`。
- Rust/Cargo：`cargo check`。
- Python + `PYTHONUTF8=1`：session-handoff 生成与验证。

### Active Processes

- 没有需接管的 Tauri dev server、Harmony 构建进程或后台监控任务。

### Environment Variables

- `PYTHONUTF8`：handoff 工具需要。
- `JAVA_HOME`、`DEVECO_SDK_HOME`：后续 Harmony CLI 构建时按 `AGENTS.md` 设置；本轮未使用。

## Related Resources

- [上一份 W2W-12 handoff](./2026-07-17-202504-eggclip-w2w12-automation-ready-w2w13-acceptance.md)
- [Windows 客户端互联 Roadmap](../../docs/Windows客户端互联剪贴板ROADMAP.md)
- [发布与回滚清单](../../docs/RELEASE.md)
- [手动回归清单](../../docs/MANUAL_REGRESSION.md)
- [桌面开发说明](../../desktop/README.md)
- [项目开发约定](../../AGENTS.md)

---

**Security Reminder**: 正式发布前重新运行版本元数据和发布安全检查，禁止在输出、提交或 handoff 中包含签名密码、证书路径、邀请秘密、密钥、剪贴板正文或完整网络帧。
