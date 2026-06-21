# Handoff: EggClip D1/H1 手动互通与 POC 边界加固完成

## Session Metadata

- Created: 2026-06-21 20:18:50
- Project: `D:\Develop\eggclip`
- Branch: `main`
- Session duration: 约 1 小时，完成桌面出站 POC、两端边界统一、回归测试和文档同步。
- Current HEAD: `352d35d`
- Upstream: `origin/main` 同样位于 `352d35d`

### Recent Commits

- `352d35d feat: 统一文本边界与严格IPv4验证，重构消息解析并增加回归测试`
- `f0f6f30 feat: 桌面端新增手动IPv4/端口连接另一桌面POC功能，更新文档和测试`
- `bb17775 feat: 增加局域网候选地址诊断、POC peer状态和动态连接状态`
- `a02e07f docs: 添加EggClip双端mDNS POC与模拟器网络结论交接文档`
- `d6ac742 feat: 实现 D1/H1 POC 核心功能：桌面 mDNS 发布、回环抑制、HarmonyOS mDNS 搜索与生命周期管理`

## Handoff Chain

- Continues from: [2026-06-21-122354-eggclip-mdns-poc-and-emulator-findings.md](./2026-06-21-122354-eggclip-mdns-poc-and-emulator-findings.md)
  - Previous title: EggClip 双端 mDNS POC 与模拟器网络结论
- Supersedes: None. This handoff extends the mDNS POC milestone with desktop outbound connectivity and consistent cross-end limits.

## Current State Summary

D1/H1 的可实现 POC 代码已基本闭合。桌面端现在既能监听入站 WebSocket，也能由用户在面板输入另一桌面实例的 IPv4/端口建立出站连接；入站和出站复用同一个收发处理路径。Desktop ↔ Desktop/HarmonyOS 继续使用临时 `clipboardText` JSON，由用户显式发送和复制，未启用未认证自动同步。两端现在统一执行正文非空且最大 256 KiB、外层 WebSocket POC 帧最大 1 MiB；Harmony 手动地址只接受有效 IPv4，并提供中文参数/连接错误。自动化验证全部通过，代码已同步到 `origin/main`。当前工作树只有本 handoff 文件未跟踪。

## Architecture Overview

- 桌面端 `transport/` 同时承载 D1 WebSocket server 和手动 outbound client。`handle_poc_websocket` 是两种连接的共用帧收发路径，Svelte 仍只通过类型化 Tauri command/event 访问它。
- 桌面 `clipboard::ClipboardText` 是 POC 正文的唯一大小边界；transport 解析成功后必须再次经过该类型，不能直接把远端字符串发送到 UI。
- Harmony `WebSocketTransportService` 只负责连接、帧编解码和连接级校验；`ClipboardBridgeService` 只处理 PasteButton 授权后的读取和用户触发写入。
- Harmony 的 UTF-8 计数集中在 `harmony/entry/src/main/ets/utils/TextLimits.ets`，clipboard 和 transport 必须共享它，避免相同文本在发送、接收和复制路径得到不同结果。
- mDNS 仍只是候选发现。桌面发布完整 `_eggclip._tcp.local.`；Harmony 查询 NetworkKit 时必须使用 `_eggclip._tcp`。
- 当前 POC 不是正式协议，不应直接向其中零散加入身份、配对或加密字段。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `desktop/src-tauri/src/transport/mod.rs` | POC server、outbound client、peer 生命周期、帧编解码 | 手动双桌面连接和 256 KiB/1 MiB 边界核心 |
| `desktop/src-tauri/src/clipboard/mod.rs` | 正文类型、系统剪贴板读写、sequence/digest/suppression | transport 必须复用 `ClipboardText::parse` |
| `desktop/src/lib/components/devices/PocConnectCard.svelte` | 手动输入另一桌面 IPv4/端口 | D1 可见的 Desktop ↔ Desktop 入口 |
| `desktop/src/lib/api/shell.ts` | Tauri command/event 类型化封装 | 不允许 Svelte 组件直接访问 socket |
| `desktop/src/lib/stores/shell.ts` | POC UI 状态和用户动作编排 | 管理连接、断开、peer 和错误反馈 |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | Harmony WebSocket、严格 IPv4、帧编解码 | Harmony 发送/接收边界的事实实现 |
| `harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets` | PasteButton 后读取和用户点击写入 | 保持 Harmony 剪贴板平台边界 |
| `harmony/entry/src/main/ets/utils/TextLimits.ets` | 256 KiB 常量和 UTF-8 字节计数 | 两条 Harmony 路径共享，不能复制实现 |
| `harmony/entry/src/test/LocalUnit.test.ets` | H1 mDNS、端点、帧、UTF-8 边界单测 | 验证桌面兼容 JSON 和超限拒绝 |
| `docs/MANUAL_REGRESSION.md` | POC 人工回归清单 | 当前勾选状态与 TODO/旧 handoff 有冲突，恢复后先核实 |
| `DESKTOP_DEVELOPMENT_TODO.md` | 桌面阶段事实来源 | D1 仍有真机、双机、防火墙项未关闭 |
| `HARMONY_DEVELOPMENT_TODO.md` | Harmony 阶段事实来源 | H1 仍有真机网络验收未关闭 |

## Key Patterns Discovered

- 256 KiB 是剪贴板正文限制；1 MiB 只是外层临时帧的快速拒绝上限，二者不能混为一谈。
- Desktop ↔ Desktop 和 Desktop ↔ Harmony 的 POC JSON 形状相同：`{"kind":"clipboardText","text":"..."}`。Rust 100 条编解码测试和 ArkTS 精确 JSON 断言用于防止两端漂移。
- 两端手动入口都只接受 IPv4。允许回环地址便于本机测试，拒绝域名、未指定地址、组播地址、全局广播地址和无效端口。
- 未认证 POC 收到文本后只进入预览，用户必须点击复制；本机剪贴板事件也必须由用户点击发送。
- Windows/Tauri dev URL 保持 `127.0.0.1`，避免 VPN 环境下 `localhost` 解析或代理干扰。

## Tasks Finished

- [x] 桌面端增加手动 IPv4/端口 outbound WebSocket command 和 8 秒连接超时。
- [x] 桌面 UI 增加“连接另一桌面 POC”和“断开全部”操作。
- [x] 入站、出站 WebSocket 复用同一帧收发和 peer 生命周期路径。
- [x] stop POC 时关闭当前临时 peer，断开的 sender 会被清理。
- [x] Rust 抽出 POC 文本解析边界，拒绝空文本、正文超 256 KiB、帧超 1 MiB和非法 JSON。
- [x] Rust 增加 100 条中文/Emoji POC 消息编解码回归。
- [x] Harmony 抽出共享 UTF-8 字节计数，clipboard 和 transport 使用同一正文限制。
- [x] Harmony 发送和接收同时拒绝空文本及超过 256 KiB 的正文。
- [x] Harmony 手动地址改为严格 IPv4，连接参数和 POC 错误改为中文。
- [x] 更新根 README、桌面 README 和双端 TODO 当前状态。

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `desktop/src-tauri/Cargo.toml` | 为 tokio 增加 outbound 连接所需 feature | 支持超时和通用异步 WebSocket IO |
| `desktop/src-tauri/src/lib.rs` | 注册 connect/disconnect Tauri commands | 暴露受控的后端连接入口 |
| `desktop/src-tauri/src/transport/mod.rs` | outbound client、共用 handler、严格端点、解析边界和测试 | 完成 D1 双桌面手动互通并收紧输入 |
| `desktop/src/lib/api/shell.ts` | 增加 connect/disconnect API | 保持组件与 Tauri 边界 |
| `desktop/src/lib/stores/shell.ts` | 增加连接编排和通用远端 POC 状态 | 不再把 peer 文案限定为 Harmony |
| `desktop/src/lib/components/devices/PocConnectCard.svelte` | 新增手动 IPv4/端口卡片 | 提供可见 D1 功能入口 |
| `desktop/src/routes/+page.svelte` | 装配新连接卡片 | 页面保持组合职责 |
| `desktop/src/app.css` | 新卡片、输入和操作样式 | 延续 EggClip 暖黄轻量风格 |
| `harmony/entry/src/main/ets/utils/TextLimits.ets` | 新增健壮 UTF-8 字节计数 | 消除 clipboard/transport 重复和边界漂移 |
| `harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets` | 改用共享计数 | 保持 PasteButton 路径行为不变 |
| `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets` | 严格 IPv4、中文错误、发送/接收 256 KiB 校验 | 与桌面端和产品边界一致 |
| `harmony/entry/src/test/LocalUnit.test.ets` | 增加端点、JSON、正文/帧边界测试 | 提供 H1 自动化回归 |
| `README.md`, `desktop/README.md`, 双端 TODO | 更新当前能力与验证数量 | 用户可见行为和计划保持同步 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| POC 正文 256 KiB，外层帧 1 MiB | 两者都用 1 MiB；两者都用 256 KiB；分层限制 | 产品明确单条正文最大 256 KiB；较大的帧上限用于快速防护 JSON 开销和异常输入 |
| Harmony 复用单一 UTF-8 计数函数 | clipboard/transport 各自实现；抽出共享工具 | 两个旧实现会漂移，且旧高代理项处理不够严谨 |
| 手动地址只支持 IPv4 | 支持域名/IPv6；保持“手动 IP”且与桌面一致 | D1/mDNS 当前都是 IPv4，避免未验证 URL 拼接和解析行为 |
| 允许 `127.0.0.1` | 全部非私网地址拒绝；允许回环 | 本机双实例/诊断仍需要回环，正式局域网使用候选私有地址 |
| 不把 100 条 codec 测试当成双机网络验收 | 自动测试代替人工验收；明确区分 | codec 回归不覆盖 Windows 防火墙、路由、断连和真实 socket 长时间行为 |

## Immediate Next Steps

1. 先核对 `docs/MANUAL_REGRESSION.md` 的全勾选是否来自真实设备/双机测试。它与双端 TODO 及上一 handoff 的“尚未真机验收”结论冲突；没有用户确认和测试记录时，不得据此关闭 D1/H1。
2. 在两台 Windows 和一台 HarmonyOS 真机同一 Wi-Fi、关闭 VPN/TUN 的条件下，验证 mDNS、严格 IPv4 手动连接、256 KiB 边界、100 次真实双向传输、断连、前后台和 PasteButton。
3. 验证 Windows 防火墙首次提示以及专用/公用网络差异，并把可复现结论写入 `docs/MANUAL_REGRESSION.md` 和对应 TODO。
4. D1/H1 明确验收后，再按 TODO 进入 D2/H2 的本地模型、store 和 SQLite/RDB；不要直接把 POC JSON 当作正式协议。

## Blockers/Open Questions

- [ ] HarmonyOS 真机 mDNS/WebSocket/PasteButton 联合验收是否已真实完成，需要用户确认或重新执行。
- [ ] 两台 Windows 的 100 次真实 socket 互传、防火墙专用/公用网络和断连恢复仍缺少可核验记录。
- [ ] `docs/MANUAL_REGRESSION.md` 全部已勾选，但双端 TODO 仍明确保留人工项；恢复时必须先消除这个事实冲突。
- [ ] Windows 剪贴板历史/监控排除格式仍需调研并决定 D1 实现范围。
- [ ] 历史 Harmony 签名配置风险仍由用户决定轮换材料或进一步处理历史；不要输出任何受保护字段。

## Deferred Items

- D2/H2 的数据模型、store、SQLite/RDB、retention 和 history：等待 D1/H1 验收边界明确。
- 正式 protocol schema、配对、身份、AEAD 和防重放：当前 POC 不具备可演进为正式协议的安全基础。
- 自动发现/自动重连/最近地址回退：属于正式 ConnectionManager 阶段。
- 未认证自动广播或自动写入：明确禁止，不是待补功能。

## Important Context

EggClip v1 是纯局域网文本剪贴板同步，不做账号、云端或公网中继。当前 `clipboardText` WebSocket 是未认证、未加密的开发 POC，只能在可信开发网络使用。桌面和 Harmony 收到内容后都只显示预览，必须由用户点击复制；本机剪贴板变化也必须由用户点击发送。正文限制是非空且最多 256 KiB，1 MiB 只用于外层帧保护。桌面完整 mDNS 服务类型是 `_eggclip._tcp.local.`，Harmony NetworkKit 查询参数必须是 `_eggclip._tcp`，不得重新合并。模拟器开启 VPN TUN 后可发现服务只是虚拟网络现象，VPN/TUN 不是产品前置条件。恢复工作时优先解决人工回归文档与 TODO 的状态冲突；在 D1/H1 未明确验收前，不应跨阶段堆叠 D2/H2 或正式安全协议。

## Assumptions Made

- `352d35d` 和 `f0f6f30` 已包含本 handoff 描述的全部功能，且 `main` 与 `origin/main` 一致。
- 用户没有要求创建新分支、额外提交、发布安装包或处理签名历史。
- Windows 仍是 v1 唯一承诺桌面平台；Harmony 目标 SDK 仍为 6.1.1(24)，compatible SDK 为 6.1.0(23)。
- 当前运行的 Tauri/Vite/eggclip 进程属于用户的开发会话，不应在恢复时擅自终止。

## Potential Gotchas

- `docs/MANUAL_REGRESSION.md` 当前全勾选不能自动视为事实；它与更高优先级的双端 TODO 和上一 handoff 冲突。
- Harmony 构建对 pasteboard 读取给出 `READ_PASTEBOARD` 静态警告是当前已知现象；产品路径仍必须由真实 PasteButton 用户授权触发，不能改为申请普通后台读取权限。
- Harmony 共享构建没有 signingConfig 的警告是预期结果；不要复制或输出本机签名材料。
- `POC_MAX_FRAME_BYTES` 不是正文上限；不要把 256 KiB 校验改回 1 MiB。
- Harmony 严格 IPv4 会拒绝域名、IPv6、前导零、0.0.0.0、组播和广播地址，这是本轮刻意行为。
- `pnpm tauri dev` 的 URL 必须保持 `127.0.0.1`，VPN 环境不要改回 `localhost`。
- 当前已有 dev 进程，重复执行 `pnpm tauri dev` 可能出现端口 1420 被占用或单实例唤醒现象。

## Environment State

### Tools/Services Used

- PowerShell，工作目录 `D:\Develop\eggclip`
- Node.js/pnpm、Rust/Cargo、Tauri 2、Svelte 5
- DevEco Studio JBR、HarmonyOS SDK 6.1.1(24)、Hvigor
- `session-handoff` scripts with `PYTHONUTF8=1`

### Active Processes

- handoff 创建时存在 `eggclip.exe` 开发进程。
- 存在一个 Tauri CLI dev Node 进程和一个 Vite dev Node 进程。
- 恢复时先检查这些进程是否仍存在；不要仅凭旧 PID 操作，也不要擅自结束用户会话。

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
- `cargo test`: passed，18 tests
- HarmonyOS `hvigorw.bat test --no-daemon`: passed
- HarmonyOS `hvigorw.bat assembleHap --no-daemon`: passed
- `git diff --check`: passed
- Harmony 构建仍有预期的 pasteboard 权限静态警告和未配置共享签名警告

Git snapshot:

- Branch: `main`
- HEAD/upstream: `352d35d`
- Tracked files: clean
- Untracked: `.claude/handoffs/2026-06-21-201850-eggclip-d1-h1-poc-boundary-hardening.md`

## Related Resources

- `AGENTS.md`
- `README.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `docs/EggClip最佳实现方案.md`
- `docs/MANUAL_REGRESSION.md`
- `desktop/README.md`
- `desktop/src-tauri/src/transport/mod.rs`
- `desktop/src-tauri/src/clipboard/mod.rs`
- `harmony/entry/src/main/ets/services/transport/WebSocketTransportService.ets`
- `harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets`
- `harmony/entry/src/main/ets/utils/TextLimits.ets`
- `.claude/handoffs/2026-06-21-122354-eggclip-mdns-poc-and-emulator-findings.md`

---

Security reminder: rerun the validator after any edit. Do not add signing material, passwords, real clipboard samples, invitations, keys, digests or complete runtime network frames.
