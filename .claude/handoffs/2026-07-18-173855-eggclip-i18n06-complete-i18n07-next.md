# Handoff: EggClip HarmonyOS I18N-06 完成，待 I18N-07 数据迁移与发布门禁

## Session Metadata

- Created: 2026-07-18 17:38:55
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: about 1 hour
- Latest commit at handoff start: `ce5ceb1 feat: 完成HarmonyOS系统资源与语言设置`
- Working tree: 18 I18N-06 files are staged; this session did not create a commit

### Recent Commits

- `ce5ceb1 feat: 完成HarmonyOS系统资源与语言设置`
- `f47ecd7 feat: 完成 Rust 错误和原生托盘国际化 (I18N-04)`
- `85348dd feat: 完成桌面端全面国际化，支持中英文即时切换`
- `951ba00 feat: 使用稳定错误码和UI消息描述符，实现双端国际化`
- `7b45a6c feat: 实现双端国际化支持，添加语言模式和相关资源文件`

## Handoff Chain

- **Continues from**: [2026-07-18-123058-eggclip-1-0-5-version-aligned-ready-for-w2w13.md](./2026-07-18-123058-eggclip-1-0-5-version-aligned-ready-for-w2w13.md)
- **Supersedes**: None. This handoff records the newer internationalization milestone; the earlier W2W acceptance context remains useful independently.

## Current State Summary

Fixed Roadmap item I18N-06 is implemented, validated, and checked in `docs/双端国际化ROADMAP.md`. HarmonyOS Home, Devices, Pairing, and Settings dynamic text now resolves through system resources; Store and WebSocket layers expose stable codes or raw values instead of localized sentences. Counts use plural resources and dates/times use the active locale. Resource parity, placeholder parity, page hardcoding, and Store/transport code boundaries are enforced by `scripts/validate-i18n-foundation.mjs`. ArkTS unit tests and `assembleHap` pass. The next complete Roadmap item is I18N-07; do not start I18N-08 or add new Roadmap tasks.

## Codebase Understanding

## Architecture Overview

- HarmonyOS presentation text lives in `entry/src/main/resources/base` for English and `zh_CN` for Simplified Chinese.
- Store and transport layers communicate user-visible state with `UiMessageDescriptor` or raw typed data. Pages resolve descriptors with `UiMessageFormatter` and perform final locale formatting.
- `LocalizedFormatter` owns `Intl.DateTimeFormat` usage. ResourceManager plural APIs own locale-sensitive singular/plural selection.
- The existing generated names such as `桌面端 #...` and `同步空间 #...` are persisted data, not runtime status text. Their provenance and migration are deliberately deferred to I18N-07.
- Internationalization integrity is checked by a repository script before release integration is added in I18N-07.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `docs/双端国际化ROADMAP.md` | Fixed internationalization execution order | I18N-06 is checked; I18N-07 is next |
| `docs/双端国际化实现方案.md` | Product and architecture decisions for both clients | Use as the design source before changing persistence |
| `harmony/entry/src/main/ets/services/localization/UiMessageCodes.ets` | Stable UI message codes and safe parameters | Store/Service language boundary |
| `harmony/entry/src/main/ets/services/localization/UiMessageFormatter.ets` | Resolves descriptors against current resources | Page formatting boundary |
| `harmony/entry/src/main/ets/services/localization/LocalizedFormatter.ets` | Locale-aware time and date formatting | Newly added in I18N-06 |
| `harmony/entry/src/main/resources/base/element/string.json` | English strings | Must stay key/placeholder-compatible with `zh_CN` |
| `harmony/entry/src/main/resources/zh_CN/element/string.json` | Simplified Chinese strings | Must stay key/placeholder-compatible with base |
| `harmony/entry/src/main/resources/base/element/plural.json` | English plural forms | Newly added for counts, seconds, and days |
| `harmony/entry/src/main/resources/zh_CN/element/plural.json` | Chinese plural forms | Must stay compatible with base |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Authenticated connection and sync state | Still contains two intentional generated-name literals for I18N-07 |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Raw history preview metadata | No longer formats localized title/source/time |
| `harmony/entry/src/main/ets/store/TrustedDeviceStore.ets` | Trusted-device summaries | Now returns raw `lastSeenAt` |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | WebSocket connection and frame diagnostics | Uses `TransportReasonCode`, not Chinese sentences |
| `scripts/validate-i18n-foundation.mjs` | Current resource and hardcoding gate | Extend or call it from the I18N-07 release gate |

## Key Patterns Discovered

- Use `UiMessageDescriptor` for Store/Service status. Only safe, bounded parameters listed in `UiMessageParameterName` are accepted.
- Use page-level `resourceText()` for dynamic string resources and `pluralText()` for quantity-dependent wording.
- `getIntPluralStringByNameSync(name, count, count)` uses the first count for plural selection and the second as the `%d` formatting argument.
- Use `LocalizedFormatter.formatTime()` or `formatDateTime()` for persisted timestamps; do not preformat time in repositories or Stores.
- Never branch UI color or behavior by translated text. Branch on enums such as `ConnectionState` or `PairingConnectionState`.
- Base and `zh_CN` placeholders must match in type and order. The validation script enforces `%s` and `%d` parity.

## Work Completed

## Tasks Finished

- [x] Completed all I18N-06 checklist items and checked the Roadmap section.
- [x] Migrated dynamic Home, Devices, Pairing, and Settings page text to system resources.
- [x] Converted Pairing/Poc connection sources and WebSocket failure diagnostics to stable codes.
- [x] Changed history and trusted-device summaries to expose raw source IDs and timestamps.
- [x] Added locale-aware date/time formatting and English/Chinese plural resources.
- [x] Mapped pairing, reconnect, network, clipboard, authentication, recovery, and HUKS self-test feedback to resources.
- [x] Updated ArkTS tests to assert stable transport codes and safe message parameters.
- [x] Added automated key, placeholder, plural, page-hardcoding, and Store/transport language-boundary checks.
- [x] Ran the internationalization gate, ArkTS tests, HAP assembly, and `git diff --check` successfully.

## Files Modified

| File or group | Changes | Rationale |
|---------------|---------|-----------|
| `docs/双端国际化ROADMAP.md` | Checked I18N-06 and its eight acceptance items | Keep visible progress aligned with the fixed plan |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Resource-backed runtime sync/history/copy status; raw metadata formatting | Remove page sentence concatenation and Chinese branching |
| `harmony/entry/src/main/ets/pages/DevicesPage.ets` | Resource-backed discovery, diagnostics, trusted-device and troubleshooting status | Complete English device experience |
| `harmony/entry/src/main/ets/pages/PairingPage.ets` | Resource-backed invitation, QR, confirmation, endpoint, handshake and reconnect feedback | Keep pairing actionable in both languages |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | Resource-backed policy, history, HUKS self-test and recovery feedback | Keep security diagnostics readable in both languages |
| `harmony/entry/src/main/ets/services/localization/LocalizedFormatter.ets` | Added locale-aware time/date formatter | Centralize `Intl.DateTimeFormat` |
| `harmony/entry/src/main/ets/services/localization/UiMessageCodes.ets` | Added localized source descriptors and safe short-device parameter | Keep connection sources out of Store display strings |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | Added `TransportReasonCode`; removed localized transport reasons | Decouple socket logic from display language |
| `harmony/entry/src/main/ets/store/HistoryStore.ets` | Replaced formatted title/source/time with raw metadata | Let the page format for the current locale |
| `harmony/entry/src/main/ets/store/TrustedDeviceStore.ets` | Replaced `lastSeen` display string with `lastSeenAt` | Prevent stale-language persisted snapshots |
| `harmony/entry/src/main/ets/store/PocConnectionStore.ets` | Descriptors for source plus raw timestamps | Remove runtime localization from Store |
| `harmony/entry/src/main/ets/store/PairingConnectionStore.ets` | Descriptors for source plus raw timestamps | Preserve authenticated sync behavior while decoupling UI |
| `resources/*/element/string.json` | Added complete English/Chinese dynamic message inventory | Cover all I18N-06 runtime text |
| `resources/*/element/plural.json` | Added locale-sensitive seconds, days, item and candidate forms | Correct English singular/plural behavior |
| `LocalUnit.test.ets` | Stable transport-code, safe-parameter and locale formatter tests | Avoid assertions tied to one Chinese sentence |
| `scripts/validate-i18n-foundation.mjs` | Added resource references, placeholder/plural parity, and hardcoding gates | Prevent internationalization regressions |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Format at the page/resource boundary | Localized Store strings; page formatting | Existing architecture requires Store/Service language independence and supports live resource selection |
| Return raw timestamps and IDs | Preformatted strings; raw values | Raw values can be reformatted after language changes and are easier to test |
| Use stable transport reason codes | Chinese diagnostics; fully formed localized errors in socket layer | Diagnostics remain machine-testable and safe while Stores choose user-facing wording |
| Use Harmony plural resources | Manual `count === 1`; generic English plurals | System plural rules are correct and extensible |
| Leave generated Chinese names for I18N-07 | Translate immediately; change only new records | Correct migration requires provenance (`generated/custom`) and protection of user names |
| Add checks to the existing Node script first | Create release gate immediately | I18N-06 establishes correctness; fixed Roadmap assigns release integration to I18N-07 |

## Pending Work

## Immediate Next Steps

1. Start only I18N-07. Inspect desktop SQLite and Harmony RDB schemas, migrations, repositories, and rename paths to design a shared `generated/custom` name-origin model.
2. Implement repeatable migrations on both clients, covering empty databases, upgrades, repeated execution, foreign keys/indexes, and preservation of user-defined names.
3. Mark new default space/device names as generated; change origin to custom after rename; display known legacy generated names through current-language resources.
4. Add `scripts/check-i18n.ps1`, reuse the existing foundation checks, scan translation parameters for sensitive data, and connect the gate to desktop `release:check` and repository release safety checks.
5. Run both desktop and Harmony validation suites, then check I18N-07 only when every listed item passes.

## Blockers/Open Questions

- No implementation blocker is known.
- Phone/tablet visual smoke testing was not performed in this session. Responsive layouts, resource parity, unit tests, and HAP compilation passed; full device-language acceptance remains explicitly scheduled for I18N-08.

## Deferred Items

- I18N-07 generated/custom provenance and legacy-name migration, because it requires persistent schema changes and its own complete Roadmap iteration.
- I18N-08 cross-language Windows/HarmonyOS phone/tablet manual acceptance and documentation closeout.
- Version bump, commit, packaging, and release were not requested.

## Context for Resuming Agent

## Important Context

- The user requires one complete Roadmap item per development iteration. Follow `docs/双端国际化ROADMAP.md` exactly, do not add tasks, and check an item only after implementation and validation.
- I18N-06 is complete. The next item is I18N-07; do not redo dynamic page localization.
- Current I18N-06 changes are staged on `main`. Preserve them and do not unstage, commit, branch, or push unless the user explicitly requests it.
- The only remaining Chinese literals in the audited runtime Store/Service area are intentional generated names for I18N-07: `等待配对设备`, fallback `桌面端 #...`, and persisted `同步空间 #...` / `桌面端 #...` names.
- The validator contains a narrow allowlist for the two `PairingConnectionStore` generated-name literals. Replace/remove that allowlist when I18N-07 migrates those names.
- Do not expose or inspect protected signing material in `harmony/build-profile.json5`. Public build profiles and handoffs must remain sanitized.
- Invitation secrets, clipboard body, key material, digests, and complete frames must never be used as translation parameters or ordinary logs.

## Assumptions Made

- English is the `base` HarmonyOS resource language; Simplified Chinese is under `zh_CN`.
- The language setting continues to show the existing reopen hint; I18N-06 does not change the preference lifecycle established in I18N-05.
- Existing responsive `GridRow` layouts and bounded controls are sufficient for build-time English layout checks; manual phone/tablet acceptance belongs to I18N-08.
- Generated-name provenance needs a durable schema field or equivalent explicit marker rather than inference at every render.

## Potential Gotchas

- Running `hvigorw.bat` from `D:\Develop\eggclip` fails because the Hvigor configuration is under `harmony`. Enter `D:\Develop\eggclip\harmony` first.
- DevEco builds emit many existing ArkTS exception-handling warnings and a pasteboard permission warning. Both test and HAP builds still finish successfully.
- `git status --short` showed all 18 current changes staged at handoff time. Use `git diff --cached` to inspect them; plain `git diff` may appear empty.
- Do not localize code/status enums themselves. Resource values change, stable codes do not.
- Do not add arbitrary parameter names to `UiMessageDescriptor`; update the safe allowlist deliberately and never pass clipboard or cryptographic content.
- Avoid translated-text comparisons. Device state colors were deliberately changed to enum-based branches.
- When modifying resource files, keep base and `zh_CN` keys plus `%s`/`%d` placeholders identical. Run the gate immediately after changes.
- `AppScope` application-name resources are separate from entry module resources.

## Environment State

## Tools/Services Used

- PowerShell on Windows.
- Node.js for `scripts/validate-i18n-foundation.mjs`.
- DevEco Studio JBR, SDK, and Hvigor for HarmonyOS unit tests and HAP assembly.
- Git for staged-diff, status, and whitespace verification.

## Validation Results

- `node scripts/validate-i18n-foundation.mjs` — passed with `i18n foundation resources ok`.
- `hvigorw.bat test --no-daemon` from `harmony` — passed, `BUILD SUCCESSFUL`.
- `hvigorw.bat assembleHap --no-daemon` from `harmony` — passed, `BUILD SUCCESSFUL`.
- `git diff --check` — passed; only line-ending conversion warnings were reported.

## Active Processes

- No dev server, watcher, emulator automation, or background build was left running.

## Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8` for handoff tooling on this Windows locale

## Related Resources

- [Internationalization Roadmap](../../docs/双端国际化ROADMAP.md)
- [Internationalization implementation plan](../../docs/双端国际化实现方案.md)
- [EggClip best implementation plan](../../docs/EggClip最佳实现方案.md)
- [Repository instructions](../../AGENTS.md)
- [HarmonyOS development plan](../../HARMONY_DEVELOPMENT_TODO.md)
- [Desktop development plan](../../DESKTOP_DEVELOPMENT_TODO.md)

---

**First action for the next session:** inspect both persistence schemas and existing name-generation/rename paths, then implement I18N-07 as one complete Roadmap iteration without adding new tasks.
