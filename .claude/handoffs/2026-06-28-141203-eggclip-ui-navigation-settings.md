# Handoff: EggClip UI navigation and settings cleanup

## Session Metadata
- Created: 2026-06-28 14:12:03
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: ~1 hour

### Recent Commits (for context)
  - 78d6a23 feat: 桌面端设置改为弹出层，鸿蒙端导航改为胶囊式
  - 74faa3f feat: 在桌面端和鸿蒙端添加设置面板，支持同步、接收、写入和历史策略
  - ff425b0 feat: 新增AppSettings的Tauri命令、TypeScript API、Svelte store和Harmony SettingsStore，修复RDB事务错误处理
  - bb8f5eb docs: 添加EggClip本地剪贴板事务后广播边界handoff文档
  - b8bc82f feat: 添加本地剪贴板事务后广播边界和失败回归测试

## Handoff Chain

- **Continues from**: [2026-06-28-100926-eggclip-post-commit-broadcast.md](./2026-06-28-100926-eggclip-post-commit-broadcast.md)
  - Previous title: EggClip post-commit local clipboard broadcast boundary
- **Supersedes**: None

> Review the previous handoff for storage/sync context before continuing protocol or persistence work.

## Current State Summary

The repo is on `main`, working tree is clean, and the latest commit is `78d6a23 feat: 桌面端设置改为弹出层，鸿蒙端导航改为胶囊式`. The most recent work focused on UI direction after the user clarified the HarmonyOS recommended navigation style with a screenshot: desktop settings should be behind the top-right settings button, while Harmony should use a centered floating capsule bottom navigation with Home / Devices / Settings. Desktop now uses a top-right settings popover instead of inserting settings into the main content flow. Harmony no longer has a duplicate top-right Settings entry on the home page, uses a custom `EggBottomNav`, and has a visually consistent placeholder Devices page.

## Important Context

This is UI cleanup only; it does not change sync protocol, pairing, transport security, or clipboard semantics. The user specifically corrected the navigation target: Harmony should match a centered floating capsule bottom navigation with icon above label, not a full-width native bottom Tabs bar. Desktop should not use mobile bottom navigation; it remains a tray-sized panel where the settings button opens a popover. Keep this distinction when continuing UI work.

## Immediate Next Steps

Continue visual refinement from the current clean commit. Good next targets are: polish Harmony home cards into product UI instead of POC/debug layout, replace temporary text icons in `EggBottomNav` with real ArkUI/Image assets, and improve SettingsPage row/card styling. After any UI change, run `pnpm check/test/build`, `cargo fmt -- --check`, `cargo check`, `cargo test`, and Harmony `hvigorw.bat test` / `assembleHap`.

## Codebase Understanding

### Architecture Overview

The UI now follows separate platform shells. Desktop is a compact Tauri/Svelte tray panel: settings are secondary controls in a popover anchored to the top-right button. Harmony is a mobile app shell: `Index.ets` owns top-level navigation state and overlays a floating capsule nav above the current page. Pages still own their current state and service calls; long-term, shared visual primitives should be extracted into components to reduce page bloat.

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `AGENTS.md` | Project/product/engineering constraints | Must be read before continuing; especially UI/IP and platform boundary rules. |
| `desktop/src/routes/+page.svelte` | Desktop main panel | Settings button now toggles the settings popover. |
| `desktop/src/app.css` | Desktop visual system | Defines `.settings-popover` and panel/card styling. |
| `harmony/entry/src/main/ets/components/navigation/EggBottomNav.ets` | Harmony floating capsule nav | Implements user-confirmed navigation style. |
| `harmony/entry/src/main/ets/pages/Index.ets` | Harmony app shell | Replaces native `Tabs` with `Stack + CurrentPage + EggBottomNav`. |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Harmony home page | Top-right Settings text removed; bottom padding added for floating nav. |
| `harmony/entry/src/main/ets/pages/DevicesPage.ets` | Harmony devices page | Replaced bare text with styled placeholder card. |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | Harmony settings page | Has bottom padding for floating nav and current settings cards. |
| `DESKTOP_DEVELOPMENT_TODO.md` | Desktop plan | Notes settings popover UI. |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony plan | Notes centered capsule navigation and settings page status. |

### Key Patterns Discovered

- Desktop settings UI should remain a popover/secondary layer, not a permanent card in the main flow.
- Harmony navigation should be app-level state in `Index.ets`, while individual pages stay focused on their content.
- Harmony pages need bottom padding when a floating nav overlays the content.
- UI changes should not introduce new clipboard/network behavior unless explicitly scoped.
- Avoid copying commercial IP or Gudetama-like designs; keep EggClip’s original egg/yolk theme.

## Work Completed

### Tasks Finished

- [x] Converted desktop settings from inline card to top-right popover.
- [x] Added `aria-expanded` on the desktop settings button.
- [x] Added desktop popover styling for light and dark mode.
- [x] Removed duplicate top-right Settings button from Harmony Home.
- [x] Added `EggBottomNav` component implementing centered floating capsule navigation.
- [x] Replaced Harmony native full-width Tabs with `Stack + CurrentPage + EggBottomNav`.
- [x] Added Home / Devices / Settings navigation entries.
- [x] Reworked Harmony Devices page from bare placeholder text into a styled card.
- [x] Added bottom padding to Harmony pages so content is not hidden behind the floating nav.
- [x] Updated desktop and Harmony TODO docs to reflect completed UI work.
- [x] Ran full desktop and Harmony validation commands.

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src/routes/+page.svelte` | Renamed settings section to popover, clarified copy, added `aria-expanded`. | Align desktop settings with top-right button popover behavior. |
| `desktop/src/app.css` | Added relative panel shell and `.settings-popover` light/dark styling. | Make settings secondary and visually layered. |
| `harmony/entry/src/main/ets/components/navigation/EggBottomNav.ets` | New custom floating capsule nav component. | Match user-provided Harmony navigation screenshot. |
| `harmony/entry/src/main/ets/pages/Index.ets` | Replaced native Tabs with stateful custom navigation shell. | Avoid full-width default Tabs; support floating nav. |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | Removed top-right Settings text and added bottom padding. | Prevent duplicate settings entry and avoid nav overlap. |
| `harmony/entry/src/main/ets/pages/DevicesPage.ets` | Added styled placeholder UI. | Keep Devices tab visually coherent while full device management is pending. |
| `harmony/entry/src/main/ets/pages/SettingsPage.ets` | Added bottom padding for floating nav. | Avoid content being covered by nav. |
| `DESKTOP_DEVELOPMENT_TODO.md` | Updated settings UI note. | Keep plan aligned. |
| `HARMONY_DEVELOPMENT_TODO.md` | Updated navigation/settings notes. | Keep plan aligned. |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Desktop settings live in a popover, not inline. | Inline card, separate route/window, popover. | Desktop panel is small and task-focused; settings are secondary. |
| Harmony uses custom capsule nav, not native `Tabs`. | Native full-width `Tabs`, HDSNavigation, custom component. | User provided screenshot shows centered floating capsule; custom component is implementable now without blocking on HDS setup. |
| Keep three Harmony tabs. | Home/Settings only; Home/Devices/Settings. | Devices is a first-level domain in the app and will host pairing/device management. |
| Devices page remains placeholder but styled. | Leave bare text; implement full devices feature. | Full device management depends on pairing/security work; styled placeholder improves UI without crossing phase boundaries. |
| Use text glyphs temporarily for nav icons. | Real icon assets now; text glyphs. | Fast path to match structure; real icons should be a follow-up. |

## Pending Work

### Immediate Next Steps

1. Replace temporary Harmony bottom nav glyphs (`⌂`, `▣`, `⚙`) with real app-owned vector/image assets matching the screenshot style.
2. Refactor Harmony repeated card/section/setting row styling into reusable components (`SectionCard`, `SettingRow`, `PageHeader`) to reduce page bloat.
3. Polish Harmony Home page: make it less POC/debug-heavy, move POC diagnostics into a collapsible diagnostic card or future Settings diagnostics section.

### Blockers/Open Questions

- [ ] Confirm whether to use official HDSNavigation/HDS components later, or keep custom `EggBottomNav`.
- [ ] Need real icon assets for Home / Devices / Settings; do not use commercial IP or copied third-party icons without license clarity.
- [ ] Need visual QA on actual Harmony emulator/device because desktop compile cannot prove nav visual alignment or safe area details.
- [ ] Full device page remains blocked by pairing/trusted device implementation.

### Deferred Items

- Full Harmony device management: deferred until pairing/trusted device data is available.
- Full Settings diagnostics: deferred until formal ConnectionManager/mDNS diagnostics are ready.
- Desktop separate settings window: not needed now; popover matches panel scope.
- HDSNavigation integration: deferred until component availability/style constraints are verified in DevEco if desired.

## Context for Resuming Agent

### Important Context

The user is sensitive to UI quality and specifically pointed out that both platforms had duplicate or misplaced settings entry points. Do not add more settings controls to the main content flow. Desktop should keep a compact tray panel with a top-right popover. Harmony should keep a centered floating capsule nav and no top-right Settings button on Home. The current UI is only structurally improved; the next quality gains should come from componentizing cards/rows and replacing temporary nav icons.

### Assumptions Made

- The screenshot provided by the user is the target navigation direction for Harmony.
- Current custom ArkUI implementation is acceptable as an interim version before optional HDSNavigation adoption.
- The latest commit `78d6a23` is the desired baseline and the working tree is clean.
- UI polish should not change transport/pairing/sync semantics.

### Potential Gotchas

- `EggBottomNav` currently uses text glyphs, not real icons. This compiles but should be replaced for production polish.
- Floating Harmony nav overlays pages; every page in the app shell needs bottom padding or safe area handling.
- Desktop `.settings-popover` is absolutely positioned inside `.panel-shell`; changing panel layout may require repositioning.
- Harmony `hvigor` still emits existing warnings for Pasteboard permission and RDB throwing APIs; these are not caused by the UI nav work.
- Do not reintroduce HomePage top-right “设置” while Settings is already a bottom nav tab.

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`.
- pnpm/SvelteKit/Vite in `desktop`.
- Rust/Cargo in `desktop/src-tauri`.
- DevEco hvigor via `C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat`.
- Python handoff script with `PYTHONUTF8=1`.

### Active Processes

- No long-running dev server or background process was intentionally left running.

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Related Resources

- `AGENTS.md`
- `docs/EggClip最佳实现方案.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `.claude/handoffs/2026-06-28-100926-eggclip-post-commit-broadcast.md`

## Validation Completed

- `cd desktop; pnpm check`
- `cd desktop; pnpm test`
- `cd desktop; pnpm build`
- `cd desktop/src-tauri; cargo fmt -- --check`
- `cd desktop/src-tauri; cargo check`
- `cd desktop/src-tauri; cargo test` — 83 passed
- `cd harmony; hvigorw.bat test --no-daemon`
- `cd harmony; hvigorw.bat assembleHap --no-daemon`

Known warnings:

- Harmony static warning for `ohos.permission.READ_PASTEBOARD` in `ClipboardBridgeService.ets`.
- Harmony RDB APIs produce “Function may throw exceptions” warnings.
- Harmony `No signingConfig found for product default`.

---

**Security Reminder**: Before finalizing, run `validate_handoff.py` to check for accidental secret exposure.
