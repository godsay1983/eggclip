# Handoff: EggClip HarmonyOS 应用内评价功能完成，待真机验收

## Session Metadata

- Created: 2026-07-20 18:32:58
- Project: `D:\Develop\eggclip`
- Branch: `main`
- HEAD: `99ba105 feat: 添加HarmonyOS应用内评价功能`
- Session duration: about 1 hour
- Current versions: desktop `1.0.6`; committed HarmonyOS `1.0.7`; working-tree `harmony/AppScope/app.json5` currently shows `1.0.8` / `10008`

### Recent Commits

- `99ba105 feat: 添加HarmonyOS应用内评价功能`
- `5af2e40 docs: 添加历史上限即时刷新修复的交接文档`
- `a680385 chore: 更新版本号至1.0.7并刷新签名信息`
- `1c435a9 feat: 设置保存后即时刷新首页历史摘要`

## Handoff Chain

- **Continues from**: [2026-07-20-131347-eggclip-harmony-history-limit-live-refresh.md](./2026-07-20-131347-eggclip-harmony-history-limit-live-refresh.md)
- **Supersedes**: none

## Current State Summary

HarmonyOS 端的 AppGallery 应用内评价能力已经完成并提交。设置页新增中英文“支持 EggClip”卡片，用户可以主动拉起系统评论弹窗；系统接口不可用时才跳转 EggClip 的 AppGallery 写评论页。自动评价只在可信发送收到持久化后的 `ITEM_ACK`，或用户把远端文本成功复制到系统剪贴板后累计成功操作，并经过使用天数、活跃天数、里程碑、版本、冷却期和年度次数限制后触发。评分策略状态使用独立 Preferences 保存，不进入同步协议、剪贴板历史或备份。格式、lint、单元测试、类型检查和 HAP 构建均已通过；剩余工作是 AppGallery 可用真机上的系统弹窗验收。

## Architecture Overview

评价实现保持在 HarmonyOS 应用层，不改变桌面端和跨端协议：

1. `AppReviewPrompt` 定义持久化状态、节流常量和安全解析。
2. `AppReviewPromptRepository` 使用独立 Preferences 保存非敏感的本机评价频率状态。
3. `AppReviewPromptCoordinator` 串行处理活跃日、成功操作、里程碑和资格判断。
4. `AppReviewService` 封装 AppGallery Kit 评论弹窗和 App Linking 降级入口。
5. `EntryAbility` 只登记前台活跃日。
6. `HomePage` 从可信 ACK 和成功复制两个真实成功点记录操作，并延迟检查自动弹窗资格。
7. `SettingsPage` 提供用户主动评价入口；主动入口不受自动频率限制，但成功展示会抑制短期内的自动请求。

## Important Context

- 用户提供了华为官方“评论与评分”和“应用评论服务”PDF，以及一份既有应用的通用接入指南。本次实现遵循 `commentManager.showCommentDialog()` 的系统弹窗流程。
- 系统评论弹窗不支持模拟器，且是否实际展示仍由 AppGallery/系统环境决定。代码成功返回只表示请求被接受，不能宣称用户已经评分，也不读取评分结果。
- 自动弹窗不做 AppGallery 页面降级、不弹失败 Toast，避免打断剪贴板主流程；设置页主动入口失败时才尝试打开写评论页。
- 自动资格固定为：首次使用满 7 天、至少 3 个活跃日、成功操作跨过 10/50/100 次及之后每 100 次里程碑、同版本最多一次、90 天冷却、每年最多两次；失败后 7 天内不自动重试。
- 成功发送不是“点击发送”即计数，而是可信发送得到桌面端 ACK 且确认序号前进后计数。POC、暂停、失败和重复 ACK 均不计数。
- 评价状态的 Preferences 名称为 `eggclip_app_review_prompt`，不会进入 RDB、同步空间或云端。
- `HARMONY_DEVELOPMENT_TODO.md` 没有新增临时任务；只把既有 H7 发布验收项扩展为包含 AppGallery 应用内评价真机验证。该项仍未勾选。
- 工作区当前还有用户/本机构建产生的 `harmony/AppScope/app.json5` 修改，版本为 `1.0.8` / `10008`，且该文件可能包含本机签名配置。不要输出其中的 `material`，不要擅自还原或提交。

## Critical Files

| File | Purpose | Relevance |
|---|---|---|
| `harmony/entry/src/main/ets/models/AppReviewPrompt.ets` | 评价状态模型、常量、序列化和容错解析 | 自动触发规则的事实来源 |
| `harmony/entry/src/main/ets/data/repositories/AppReviewPromptRepository.ets` | 独立 Preferences 持久化 | 保证状态不进入业务数据库和同步 |
| `harmony/entry/src/main/ets/services/review/AppReviewPromptCoordinator.ets` | 活跃日、成功次数、里程碑和节流编排 | 自动评价策略核心 |
| `harmony/entry/src/main/ets/services/review/AppReviewRuntime.ets` | 进程内共享协调器 | Ability 和页面共享同一串行状态入口 |
| `harmony/entry/src/main/ets/services/review/AppReviewService.ets` | AppGallery Kit 和写评论页降级 | 平台能力边界 |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | 对外发布已持久化 ACK 的确认增量 | 防止点击即计数或重复计数 |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | 成功操作计数和自动弹窗检查 | 主业务接入点 |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | 主动评价卡片和降级反馈 | 用户可见入口 |
| `harmony/entry/src/test/LocalUnit.test.ets` | 状态、里程碑、冷却和 ACK 增量测试 | 回归保护 |
| `docs/MANUAL_REGRESSION.md` | 真机与降级路径验收步骤 | 发布验收依据 |

## Work Completed

### Tasks Finished

- [x] 接入 AppGallery Kit 系统评论弹窗。
- [x] 增加 AppGallery 写评论页降级入口。
- [x] 增加设置页中英文主动评价卡片，并适配 phone/tablet 布局。
- [x] 增加独立本机评价状态持久化与容错迁移。
- [x] 增加前台活跃日、可信 ACK 和成功复制计数。
- [x] 实现里程碑、版本、冷却期、年度次数和失败冷却限制。
- [x] 增加 ACK 增量、序列化、活跃日、里程碑和资格规则单元测试。
- [x] 更新根 README、Harmony README、回归清单和既有 H7 验收描述。
- [x] 完成格式、lint、测试、类型检查和 HAP 构建。

## Files Modified

The following files are included in commit `99ba105`:

| Area | Files | Changes |
|---|---|---|
| Model/storage | `AppReviewPrompt.ets`, `AppReviewPromptRepository.ets` | 新增评价策略状态与独立 Preferences |
| Services | `services/review/*` | 新增协调器、运行时单例和 AppGallery 服务 |
| Lifecycle/UI | `EntryAbility.ets`, `HomePage.ets`, `SettingsPage.ets` | 活跃日、成功操作、自动请求和主动入口 |
| Transport state | `PairingConnectionStore.ets` | 新增持久化 ACK 增量订阅 |
| Resources/tests | 两份 `string.json`, `LocalUnit.test.ets` | 中英文文案和规则测试 |
| Documentation | `README.md`, `harmony/README.md`, `docs/MANUAL_REGRESSION.md`, `HARMONY_DEVELOPMENT_TODO.md` | 行为说明与验收入口 |

## Decisions Made

| Decision | Alternatives | Rationale |
|---|---|---|
| 只在 HarmonyOS 接入评分 | 桌面端也跳转评分 | 华为能力属于 AppGallery Kit，桌面端没有对应商店交互需求 |
| 手动入口 + 克制的自动触发 | 只做按钮；启动即弹 | 既方便主动评价，又避免干扰剪贴板主流程和审核体验 |
| ACK/复制成功后计数 | 点击按钮立即计数 | 只有实际完成的用户价值动作才应进入里程碑 |
| 独立 Preferences | 写入 RDB 设置表 | 评价频率是本机 UI 状态，不应进入同步、历史或备份 |
| 自动失败静默，手动失败降级 | 自动失败也跳商店 | 自动流程不能抢占页面或破坏剪贴板交互 |
| 不记录评分内容或结果 | 尝试推断用户评分 | 平台接口不提供可靠评分结果，也不应收集这类数据 |

## Verification Completed

- `git diff --check`: passed before handoff creation.
- `harmony/scripts/check-i18n.ps1`: passed; desktop Vitest subset reported 10 tests passed.
- `harmony/scripts/test.ps1`: passed; Harmony unit-test build successful.
- `harmony/scripts/verify.ps1`: passed after fixing `GridRow.alignItems` from `VerticalAlign.Center` to `ItemAlign.Center`.
- Final verification result: format passed, lint passed with existing advisory warnings, type check passed, unit tests passed, `assembleHap` passed.
- No server or long-running process remains active.

## Immediate Next Steps

1. On a real HarmonyOS device logged into a Huawei account with AppGallery available, open **Settings → Support EggClip → Rate EggClip** and confirm the system review dialog appears without losing page state.
2. Exercise the unavailable/cancel path and confirm EggClip remains stable; when the platform call truly fails, verify the manual entry can attempt to open the `com.eggclip.app` AppGallery write-review page.
3. Confirm whether the uncommitted HarmonyOS version bump to `1.0.8` / `10008` is intentional. If preparing a dual-client release, align desktop metadata only after explicit user direction and run the full release gates.

## Pending Work

### Blockers/Open Questions

- [ ] AppGallery system review dialog needs real-device acceptance; simulator results are insufficient.
- [ ] The working-tree `harmony/AppScope/app.json5` version/signing change is not part of commit `99ba105`; its ownership and release intent need confirmation before commit.
- [ ] H7 remains pending because formal signing, package secret scan, upgrade/rollback and the new real-device rating check are release-level acceptance items.

### Deferred Items

- Automatic-prompt visual acceptance is deferred to a controlled test build or aged test state; production thresholds deliberately make it difficult to force immediately.
- Desktop rating UI is out of scope.
- No telemetry, rating-result collection or cloud state was added.

## Assumptions Made

- Production AppGallery package ID is `com.eggclip.app`.
- The user wants the official system dialog first and the application-market page only as a manual fallback.
- Successful trusted sync ACK and successful copy-to-system-clipboard are the two appropriate “value delivered” signals for automatic eligibility.

## Potential Gotchas

- Do not test the actual system dialog only in the emulator; the platform feature can fail or be suppressed there.
- Do not interpret a successful API return as proof that the user submitted a rating.
- Do not move automatic eligibility checks onto every foreground event; foreground only records active days.
- Do not count outbound attempts before durable ACK advancement, or duplicate/replayed ACKs will inflate milestones.
- Do not expose full platform errors, clipboard text, invitation data or signing material in logs or handoffs.
- `harmony/AppScope/app.json5` is sensitive local signing configuration; inspect only safe metadata when necessary.

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`.
- DevEco Studio bundled JBR and SDK through repository verification scripts.
- Hvigor unit test and `assembleHap` via `harmony/scripts/verify.ps1`.
- Session handoff scripts with `PYTHONUTF8=1` for Windows UTF-8 output.

### Active Processes

- None.

### Environment Variable Names

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `PYTHONUTF8`

## Related Resources

- `harmony/README.md`
- `docs/MANUAL_REGRESSION.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `docs/EggClip最佳实现方案.md`
- User-provided Huawei AppGallery review PDFs and `HARMONY_APP_REVIEW_INTEGRATION_GUIDE.md` on the desktop (external reference files, not copied into this repository).

---

**Security note**: this handoff intentionally omits signing material, credentials, clipboard content and invitation secrets.
