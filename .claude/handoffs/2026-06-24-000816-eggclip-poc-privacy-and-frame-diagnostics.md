# Handoff: EggClip D1/H1 剪贴板隐私与安全帧诊断完成

## Session Metadata

- Created: 2026-06-24 00:08:16
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: 约 2 小时，完成 Windows 剪贴板隐私标记、Harmony 消息拒绝分类、双端安全帧诊断和完整验证。
- Current HEAD: `6888e44`
- Upstream: `origin/main` 同样位于 `6888e44`

### Recent Commits

- `6888e44 feat: 添加POC帧诊断计数与显示`
- `800c910 feat: 支持Windows剪贴板隐私标记，改进HarmonyOS消息解码`
- `b6e14d8 docs: 添加EggClip D1/H1手动互通与POC边界加固完成交接文档`
- `352d35d feat: 统一文本边界与严格IPv4验证，重构消息解析并增加回归测试`
- `f0f6f30 feat: 桌面端新增手动IPv4/端口连接另一桌面POC功能，更新文档和测试`

## Handoff Chain

- Continues from: [2026-06-21-201850-eggclip-d1-h1-poc-boundary-hardening.md](./2026-06-21-201850-eggclip-d1-h1-poc-boundary-hardening.md)
  - Previous title: EggClip D1/H1 手动互通与 POC 边界加固完成
- Supersedes: None. This handoff extends the D1/H1 POC with privacy-marker handling and safe diagnostics.

## Current State Summary

D1/H1 可在代码层完成的 POC 安全边界已进一步收口。Windows 剪贴板监听现在会跳过带 `ExcludeClipboardContentFromMonitorProcessing` 或 `CanUploadToCloudClipboard=0` 的来源内容；EggClip 写入系统剪贴板时会设置禁止 Windows 云剪贴板上传，但不会主动排除本机剪贴板历史。HarmonyOS 收到非法 JSON、错误消息类型、空文本、超限正文或二进制消息时会显示不同拒绝原因。桌面和 HarmonyOS 都新增了不含正文的接收、接受、拒绝计数及上次拒绝类型。完整自动化、HAP 编译和 Tauri dev 冒烟均通过，代码已进入 `6888e44` 并同步到 `origin/main`。当前工作区只有本 handoff 文件未跟踪。

## Architecture Overview

- 桌面 `clipboard/` 是系统剪贴板和同步隐私策略边界。监控线程在同一次 Windows clipboard lock 中读取注册格式和 Unicode 文本，避免标记与正文来自不同 clipboard sequence。
- 桌面 EggClip 写入统一经过 `set_eggclip_clipboard_text`；Windows 使用 arboard 的 `SetExtWindows::exclude_from_cloud()`，其他平台保持普通文本写入，但 Windows 仍是 v1 唯一承诺桌面平台。
- 排除标记只影响是否形成本机同步候选。远端写入仍先经过 suppression 分类，从而消费回环 token，再根据来源标记决定是否向 UI 发出本机事件。
- 桌面 `transport/` 的 `PocTransportDiagnostics` 只保存帧数和枚举拒绝类型，通过 `transport://poc-diagnostics` 事件交给 Svelte store。
- Harmony `WebSocketTransportService` 持有当前 POC 会话的安全诊断；每次有效 connect 重置，字符串帧解码和二进制拒绝都会更新计数。
- 两端诊断 UI 只显示数量和拒绝分类，不保存或输出正文、摘要、邀请、密钥或完整网络帧。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/src-tauri/src/clipboard/mod.rs` | Windows clipboard 读写、隐私标记、回环抑制 | 监听排除和云剪贴板禁止上传的核心实现 |
| `desktop/src-tauri/src/transport/mod.rs` | POC 连接、消息解析和安全帧诊断 | Rust 端接收/接受/拒绝统计和枚举原因 |
| `desktop/src/lib/types/shell.ts` | Svelte shell 与 POC 诊断类型 | 保持 Rust event 与前端严格类型一致 |
| `desktop/src/lib/api/shell.ts` | Tauri command/event 类型化封装 | 监听 `transport://poc-diagnostics` |
| `desktop/src/lib/stores/shell.ts` | UI 状态编排 | 把诊断事件写入 shell snapshot |
| `desktop/src/lib/components/devices/PocConnectCard.svelte` | 手动连接和诊断展示 | 显示帧数及中文拒绝标签 |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | WebSocket、消息解码、诊断状态 | Harmony 接收分类和安全计数事实来源 |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | H1 页面编排 | 展示帧诊断及具体拒绝原因 |
| `harmony/entry/src/test/LocalUnit.test.ets` | H1 unit tests | 验证解码拒绝和诊断重置 |
| `docs/MANUAL_REGRESSION.md` | 双端人工回归清单 | 新增剪贴板隐私标记和 POC 安全帧诊断项 |
| `DESKTOP_DEVELOPMENT_TODO.md` | 桌面阶段事实来源 | D1 仍有 Windows 真机/防火墙验收 |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony 阶段事实来源 | H1 仍有真机网络验收 |

## Key Patterns Discovered

- Microsoft 定义 `ExcludeClipboardContentFromMonitorProcessing` 为“任意数据即排除历史和跨设备同步”；`CanUploadToCloudClipboard` 使用 DWORD 0/1 控制跨设备上传。EggClip 对存在但损坏的上传许可标记采取保守拒绝。
- `CanIncludeInClipboardHistory=0` 只控制本机 Windows 历史，不代表禁止 EggClip 局域网同步，因此当前监听不会据此丢弃内容。
- EggClip 是纯局域网工具，所以任何由 EggClip 写入 Windows clipboard 的文本都会带 `CanUploadToCloudClipboard=0`；本机系统历史仍可保留该文本。
- 诊断必须是 bounded metadata。拒绝原因使用固定枚举或固定中文分类，不能附带原始 JSON、正文或 peer 完整帧。
- 桌面端收到二进制 POC 帧会记录拒绝并断开该 POC；Harmony 端会记录二进制拒绝并显示错误。
- 256 KiB 仍是正文限制，1 MiB 仍只是外层 POC 帧限制；诊断功能没有改变该边界。

## Tasks Finished

- [x] 调研 Microsoft 官方 Cloud Clipboard/Clipboard History 注册格式语义。
- [x] Windows 监听跳过 `ExcludeClipboardContentFromMonitorProcessing`。
- [x] Windows 监听跳过 `CanUploadToCloudClipboard=0`，损坏许可值保守视为不可上传。
- [x] EggClip Windows 写入设置禁止云剪贴板上传，同时保留本机系统历史能力。
- [x] 标记读取与 Unicode 文本读取使用同一次 clipboard lock。
- [x] Harmony 解码返回结构化成功/失败结果，区分 JSON、类型、空文本和超限正文。
- [x] 桌面增加 `PocTransportDiagnostics`、固定拒绝枚举和诊断 event。
- [x] Svelte 手动连接卡片显示接收、接受、拒绝数及上次拒绝分类。
- [x] Harmony transport 统计相同维度，HomePage 显示诊断字符串。
- [x] 增加 Rust 隐私标记单测和 ArkTS 诊断单测。
- [x] 更新根 README、桌面 README、双端 TODO 和人工回归清单。

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src-tauri/src/clipboard/mod.rs` | 读取注册格式、禁止云上传、排除同步候选和测试 | 尊重来源隐私并维持纯局域网边界 |
| `desktop/src-tauri/src/transport/mod.rs` | 诊断模型、拒绝枚举、计数 event、二进制拒绝 | 为真机/双机验收提供不泄露正文的观测 |
| `desktop/src/lib/types/shell.ts` | 新增 POC 诊断和拒绝原因类型 | 端到端类型化 event payload |
| `desktop/src/lib/api/shell.ts` | status 诊断字段和 event listener | 封装 Tauri event |
| `desktop/src/lib/stores/shell.ts` | 诊断写入 snapshot | 页面组件不直接监听 Tauri |
| `desktop/src/lib/components/devices/PocConnectCard.svelte` | 中文拒绝标签和统计显示 | 提供 D1 可见诊断 |
| `desktop/src/app.css` | 诊断文本样式 | 延续轻量暖黄色视觉 |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | 结构化 decode、诊断计数和 reset | 支持 H1 安全错误分类 |
| `harmony/entry/src/main/ets/pages/HomePage.ets` | 显示诊断，拒绝时展示固定原因 | 手动回归无需读取内部日志 |
| `harmony/entry/src/test/LocalUnit.test.ets` | 解码原因和诊断状态测试 | 防止计数/重置回归 |
| `docs/MANUAL_REGRESSION.md` | 隐私标记和安全帧诊断条目 | 明确剩余人工验收 |
| `README.md`, `desktop/README.md`, 双端 TODO | 更新能力、边界和测试数量 | 文档与用户可见行为同步 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| 来源有 monitor/cloud 排除标记时不形成同步候选 | 忽略 Windows 标记；只尊重 monitor；同时尊重 cloud=0 | EggClip 也会把内容发送到另一设备，必须尊重明确的跨设备禁止意图 |
| EggClip 写入只排除 Windows cloud，不排除本机 history | 使用总排除格式；分别设置 cloud/history；只设置 cloud=0 | 保证纯局域网，不无故破坏用户本机 clipboard history |
| 损坏的 cloud permission 标记 fail closed | 忽略损坏值；按非零允许；保守拒绝 | 来源既然放置许可格式，无法解析时不应推断允许跨设备传输 |
| 诊断存固定分类和计数 | 保存完整帧方便调试；只记总数；固定分类+总数 | 能支持回归定位，同时遵守日志和隐私约束 |
| D1/H1 未验收前继续做诊断而非进入 D2/H2 | 直接开始存储；停止开发等待硬件；补验收工具 | 诊断仍属于 POC 阶段，并能降低真机验收成本 |

## Immediate Next Steps

1. 先核实 `docs/MANUAL_REGRESSION.md` 旧有全勾选项是否来自真实双机/真机结果；它与 TODO 的未完成状态存在冲突。没有测试记录或用户确认时不得关闭 D1/H1。
2. 使用 Windows 测试工具分别写入 monitor exclusion、cloud upload DWORD 0/1 和损坏值，验证 EggClip 面板事件及计数符合 `docs/MANUAL_REGRESSION.md`，且普通日志不含原始数据。
3. 在两台 Windows 与一台 HarmonyOS 真机上验证正常/非法/超限/二进制帧计数、连接重置、mDNS、PasteButton、前后台和防火墙行为。
4. 完成并记录人工验收后，再按 TODO 进入 D2/H2 的本地模型、store 和 SQLite/RDB；不要把当前 POC JSON 当作正式协议。

## Blockers/Open Questions

- [ ] HarmonyOS 真机 mDNS/WebSocket/PasteButton 联合验收缺少可核验记录。
- [ ] 两台 Windows 的 100 次真实互传、断连恢复和专用/公用防火墙行为仍需人工执行。
- [ ] Windows 隐私标记需要使用外部测试写入工具完成系统级回归；当前只完成 Rust 纯逻辑和编译验证。
- [ ] `docs/MANUAL_REGRESSION.md` 旧条目全勾选，但双端 TODO 与先前 handoff 仍标记人工项未完成。
- [ ] 历史 Harmony 签名配置风险仍由用户决定处理方式；后续不得输出受保护内容。

## Deferred Items

- D2/H2 model/store/SQLite/RDB/history/retention：等待 D1/H1 验收明确。
- 正式 protocol schema、配对、身份密钥、AEAD 和防重放：不能从未认证 POC 零散演进。
- 自动发现 ConnectionManager、心跳和退避重连：属于后续正式网络阶段。
- 未认证自动广播或自动写入：明确禁止，不是待实现功能。

## Important Context

EggClip v1 是纯局域网 `text/plain` 同步工具，不使用账号、云端或公网中继。当前 WebSocket `clipboardText` JSON 只是未认证、未加密的开发 POC：发送和复制都必须由用户触发。正文最大 256 KiB，外层帧最大 1 MiB。Windows 来源如果明确禁止监控或跨设备上传，EggClip 不得把该内容形成同步候选；EggClip 自己写入 Windows clipboard 时必须禁止 Windows Cloud Clipboard 上传。安全诊断只能记录接收、接受、拒绝数量和固定拒绝类型，不能记录正文、摘要或完整帧。桌面发布类型 `_eggclip._tcp.local.` 与 Harmony 查询类型 `_eggclip._tcp` 仍必须分开。模拟器依赖 VPN TUN 的发现结果只是虚拟网络现象，不是产品要求。恢复后不要根据 `docs/MANUAL_REGRESSION.md` 的旧勾选直接宣布 POC 验收完成，必须先解决它与 TODO/测试记录的冲突。

## Assumptions Made

- `6888e44` 和 `800c910` 已包含本 handoff 描述的全部业务变化，`main` 与 `origin/main` 一致。
- 用户没有要求创建分支、额外提交、发布安装包或处理签名历史。
- Windows 是 v1 唯一承诺桌面平台；Harmony 目标仍为 SDK 6.1.1(24)，compatible SDK 6.1.0(23)。
- 当前没有需要下一会话接管的 Tauri、Cargo、Vite 或 EggClip 后台进程。

## Potential Gotchas

- `CanIncludeInClipboardHistory=0` 不等于禁止 EggClip LAN 同步；不要无依据扩大其语义。
- `CanUploadToCloudClipboard` 是 serialized Windows DWORD。0 禁止，1 允许；存在但缺失/损坏/其他值时当前实现保守拒绝。
- 监听排除判断和正文读取必须在同一个 clipboard lock 内，否则 clipboard sequence 变化会导致策略应用到错误内容。
- EggClip 写入使用 `exclude_from_cloud()`，不是 `exclude_from_monitoring()`；改成总排除会让内容无法进入本机 Windows 历史。
- 桌面诊断 reset 发生在新的 POC server 启动；Harmony 诊断 reset 发生在有效 endpoint connect 开始后。
- 桌面二进制帧会记为拒绝并关闭 peer；Harmony 会记为拒绝并通过现有错误回调展示。
- Harmony pasteboard 的 `READ_PASTEBOARD` 静态警告和共享配置无 signingConfig 警告仍是预期构建结果；产品路径必须继续使用真实 PasteButton。
- Tauri dev URL 必须保持 `127.0.0.1`，VPN 环境不要改回 `localhost`。

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Node.js/pnpm、Rust/Cargo、Tauri 2、Svelte 5
- DevEco Studio JBR、HarmonyOS SDK 6.1.1(24)、Hvigor
- Microsoft Learn Clipboard Formats official documentation
- `session-handoff` scripts with `PYTHONUTF8=1`

### Active Processes

- handoff 创建前已检查，没有 EggClip、Cargo、Tauri CLI 或 Vite dev 进程需要接管。
- Tauri dev 冒烟产生的进程树已按已验证 PID 清理。

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Validation Snapshot

- `pnpm check`: passed，0 errors / 0 warnings
- `pnpm test`: passed，2 tests
- `pnpm build`: passed
- `cargo fmt -- --check`: passed
- `cargo check`: passed
- `cargo test`: passed，20 tests
- HarmonyOS `hvigorw.bat test --no-daemon`: passed
- HarmonyOS `hvigorw.bat assembleHap --no-daemon`: passed
- `pnpm tauri dev`: app/Vite/Cargo/WebView2 process tree launched successfully for smoke verification, then cleaned up
- `git diff --check`: passed
- Harmony 构建仍有预期 pasteboard 权限静态警告和无共享签名警告

Git snapshot:

- Branch: `main`
- HEAD/upstream: `6888e44`
- Tracked files: clean
- Untracked: `.claude/handoffs/2026-06-24-000816-eggclip-poc-privacy-and-frame-diagnostics.md`

## Related Resources

- `AGENTS.md`
- `README.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `docs/EggClip最佳实现方案.md`
- `docs/MANUAL_REGRESSION.md`
- `desktop/README.md`
- `desktop/src-tauri/src/clipboard/mod.rs`
- `desktop/src-tauri/src/transport/mod.rs`
- `desktop/src/lib/components/devices/PocConnectCard.svelte`
- `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets`
- `harmony/entry/src/main/ets/pages/HomePage.ets`
- `harmony/entry/src/test/LocalUnit.test.ets`
- `.claude/handoffs/2026-06-21-201850-eggclip-d1-h1-poc-boundary-hardening.md`
- [Microsoft Clipboard Formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats#cloud-clipboard-and-clipboard-history-formats)

---

Security reminder: rerun the validator after any edit. Never add signing material, passwords, real clipboard samples, invitations, keys, digests or complete runtime network frames.
