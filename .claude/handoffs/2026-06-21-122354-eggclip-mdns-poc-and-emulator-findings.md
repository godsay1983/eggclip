# Handoff: EggClip 双端 mDNS POC 与模拟器网络结论

## Session Metadata

- Created: 2026-06-21 12:23:54
- Project: D:\Develop\eggclip
- Branch: main
- Session duration: 约 1.5 小时，完成双端 mDNS POC、Windows 回环抑制基础、HarmonyOS 前后台生命周期，并处理模拟器 mDNS 错误。

### Recent Commits (for context)

- d6ac742 feat: 实现 D1/H1 POC 核心功能：桌面 mDNS 发布、回环抑制、HarmonyOS mDNS 搜索与生命周期管理
- d232572 docs: 添加D1/H1双端POC稳定化交接文档
- f9a2947 feat: 实现 POC 连接生命周期管理，包括超时、断开按钮、页面销毁清理和消息大小校验
- f4ac6ea feat: 实现桌面端断开连接清理和鸿蒙端手动复制到本机功能
- cbe13af feat: 完成桌面↔Harmony双向文本传输POC

## Handoff Chain

- Continues from: [2026-06-21-104915-eggclip-h1-d1-poc-stabilized.md](./2026-06-21-104915-eggclip-h1-d1-poc-stabilized.md)
  - Previous title: EggClip D1/H1 双端 POC 稳定化完成
- Supersedes: None. This handoff extends the previous POC baseline with mDNS and lifecycle work.

## Current State Summary

EggClip 的 D1/H1 POC 已增加桌面端最小 mDNS 发布和 HarmonyOS 前台 mDNS 搜索。桌面 WebSocket POC server 启动时通过 `mdns-sd` 发布 `_eggclip._tcp.local.`，TXT 只包含 POC 协议标记、临时实例 ID 和能力位；HarmonyOS 解析候选 IPv4/端口，去重后允许用户点击连接，同时保留手动 IP。HarmonyOS 进入后台时会停止发现并断开 WebSocket，回到前台时重新发现，并在此前已连接时尝试重连。Windows 侧完成 digest、clipboard sequence 和短时 suppression token 的真实运行时基础，但未认证 POC 不会调用自动写入策略。上述业务代码与文档已在 `d6ac742` 提交并同步到 `origin/main`；当前工作区只有本 handoff 文档未跟踪。

## Architecture Overview

桌面端新增 `discovery/` 和 `sync/` 边界。`transport/` 启停 POC server 时装配 mDNS 发布，但 mDNS 只提供候选地址；未认证 WebSocket 文本仍只进入 UI 预览。`sync::apply_authenticated_live_item` 是未来认证 `ITEM_LIVE` 的自动写入入口，`clipboard::ClipboardRuntime` 管理回环抑制状态。HarmonyOS 的 `MdnsDiscoveryService` 封装 NetworkKit mDNS 生命周期、解析、去重和候选限制，`HomePage` 只呈现候选并编排用户连接；`EntryAbility` 通过 AppStorage 向页面传递前后台状态。

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| desktop/src-tauri/src/discovery/mod.rs | 桌面 mDNS POC 注册、注销和安全 TXT 属性 | 下一步处理物理网卡优先与 VPN/TUN 过滤 |
| desktop/src-tauri/src/transport/mod.rs | POC WebSocket server 生命周期与 mDNS 发布装配 | mDNS 发布和 server 端口必须一致 |
| desktop/src-tauri/src/clipboard/mod.rs | Windows clipboard sequence、digest 和 suppression tracker | 认证 ITEM_LIVE 自动写入前必须复用 |
| desktop/src-tauri/src/sync/mod.rs | 认证在线事件自动写入策略入口 | 未认证 POC 不得调用 |
| harmony/entry/src/main/ets/models/PocModels.ets | 完整 DNS-SD 名称与 Harmony 查询类型常量 | 两种字符串不能混用 |
| harmony/entry/src/main/ets/services/discovery/MdnsDiscoveryService.ets | Harmony mDNS 搜索、解析、去重、清理和错误提示 | 模拟器错误与真机验证的核心文件 |
| harmony/entry/src/main/ets/pages/HomePage.ets | 候选列表、连接入口和前后台编排 | 手动 IP fallback 必须保留 |
| harmony/entry/src/main/ets/entryability/EntryAbility.ets | 发布前后台状态 | 后台时停止 mDNS/WebSocket |
| docs/MANUAL_REGRESSION.md | 双端真机与网络回归清单 | 下一轮真机验证按此执行 |
| DESKTOP_DEVELOPMENT_TODO.md | 桌面阶段状态 | D1 真机闭环和 D4 正式发现仍未完成 |
| HARMONY_DEVELOPMENT_TODO.md | HarmonyOS 阶段状态 | H1 仅剩真机网络验收 |

## Key Patterns Discovered

- 完整 DNS-SD 类型是 `_eggclip._tcp.local.`，用于桌面发布和 UI 说明；Harmony `createDiscoveryService` 的查询参数必须是 `_eggclip._tcp`，不能携带 `.local.`。
- 本机 SDK 把 `MdnsError.INTERNAL_ERROR` 定义为错误码 `0`。模拟器出现该错误可能是查询参数错误，也可能是虚拟网络不支持局域网组播。
- 用户实测 HarmonyOS 模拟器只有开启 VPN TUN 后才能发现桌面服务。这是模拟器/NAT/TUN 路由现象，不应成为产品依赖；真机同 Wi-Fi、关闭 VPN 才是正式验收条件。
- 当前桌面发布使用 `ServiceInfo::enable_addr_auto()`，可能同时发布物理网卡、VPN 和 TUN 地址。正式发现阶段应过滤或排序虚拟网卡，优先可达的私有局域网 IPv4。
- 未认证 POC 只能由用户显式发送和复制。不能因为已完成 suppression tracker 就自动广播本机剪贴板或自动写入远端文本。

## Tasks Finished

- [x] 桌面端新增 `_eggclip._tcp.local.` 最小 mDNS POC 发布，并随 WebSocket server 停止而注销。
- [x] 桌面 TXT 只发布 `protocolVersion`、临时 `instanceId` 和 `capabilities`，不发布设备名、正文或长期身份信息。
- [x] HarmonyOS 接入 NetworkKit mDNS 搜索、服务解析、IPv4 候选过滤、重复回调去重和候选数量限制。
- [x] HarmonyOS 首页增加开始/停止发现、候选地址/端口/协议标记和点击连接入口。
- [x] HarmonyOS 页面销毁和应用后台时停止发现与 WebSocket，回前台恢复搜索并按条件重连。
- [x] Windows suppression tracker 接入 clipboard sequence，移除永久吞掉相同 digest 的旧逻辑，并增加重复文本 sequence 测试。
- [x] 建立认证在线事件的 `sync` 自动写入边界，同时明确未认证 POC 不调用。
- [x] 修正 Harmony mDNS 查询类型：完整发布名称与 Harmony API 查询字符串分离。
- [x] 将错误码 `0` 映射为模拟器/组播限制提示，并保留手动 IP 回退文案。
- [x] 更新 README、双端 TODO 和 `docs/MANUAL_REGRESSION.md`。

## Files Modified

当前功能修改已进入提交 `d6ac742`，工作区不再有未提交业务代码。该提交包含 19 个文件，重点如下：

| File | Changes | Rationale |
|------|---------|-----------|
| desktop/src-tauri/Cargo.toml | 增加 `mdns-sd` 依赖 | Windows 端发布 DNS-SD 服务 |
| desktop/src-tauri/src/discovery/mod.rs | 新增 POC 发布、注销、临时实例和 TXT 测试 | 为 Harmony H1 提供实际发现目标 |
| desktop/src-tauri/src/clipboard/mod.rs | 运行时 suppression 状态和 sequence 分类 | 为未来认证在线事件防回环 |
| desktop/src-tauri/src/sync/mod.rs | 新增认证 live 自动写入入口 | 让写入策略不落入 transport |
| desktop/src-tauri/src/transport/mod.rs | server 启停联动 mDNS，状态增加发布结果 | 保证发现端口与实际监听一致 |
| harmony/entry/src/main/ets/services/discovery/MdnsDiscoveryService.ets | 真实 mDNS 搜索和生命周期 | 完成 H1 自动发现代码路径 |
| harmony/entry/src/main/ets/pages/HomePage.ets | 发现 UI、候选连接和生命周期响应 | 提供可见、可操作 POC |
| harmony/entry/src/main/ets/entryability/EntryAbility.ets | AppStorage 前后台信号 | 前台连接边界 |
| docs/MANUAL_REGRESSION.md | 新增双端手动回归清单 | 记录真机验收步骤 |
| .claude/handoffs/2026-06-21-122354-eggclip-mdns-poc-and-emulator-findings.md | 新增本交接文档 | 保存当前里程碑与网络结论 |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Harmony 查询类型使用 `_eggclip._tcp` | 直接传完整 `_eggclip._tcp.local.`；拆分发布和查询常量 | 本机 SDK 类型说明与模拟器错误表明 Harmony API 需要不带 `.local.` 的服务类型 |
| 未认证 POC 不自动写入或广播 | 为展示效果直接自动同步；保持用户触发 | 产品不变量要求未配对设备被拒绝，POC 不能绕过认证边界 |
| 桌面 mDNS 发布作为 H1 阻断项提前做最小 POC | 等正式 D4；当前先做安全最小发布 | 没有桌面发布，Harmony H1 无法验证真实发现；正式 ConnectionManager 仍留在 D4 |
| 模拟器 + TUN 结果只记录为诊断信息 | 把 TUN 当运行前置；只认真机 | TUN 改变虚拟网卡和路由，不能代表真实手机同 Wi-Fi 行为 |
| 保留手动 IP | 强制 mDNS；自动发现加 fallback | mDNS 可能被访客网络、AP 隔离、VPN 或模拟器 NAT 阻断 |

## Immediate Next Steps

1. 在 HarmonyOS 真机和 Windows 位于同一 Wi-Fi、双方关闭 VPN/TUN 的条件下，按 `docs/MANUAL_REGRESSION.md` 验证 mDNS 发现、候选地址、WebSocket、PasteButton 和前后台恢复。
2. 记录桌面 mDNS 实际发布的所有候选地址；若包含 VPN/TUN/虚拟网卡地址，在 `desktop/src-tauri/src/discovery/mod.rs` 增加物理私有 IPv4 优先与虚拟接口过滤，同时保留手动 IP。
3. 完成 D1 剩余真机项：连续相同文本、Windows 防火墙专用/公用网络、100 次双向手动传输和断连恢复。
4. 真机 POC 稳定后再进入 `protocol/` schema 与测试向量骨架，不能把当前 `clipboardText` JSON 直接演变成正式协议。

## Blockers/Open Questions

- [ ] HarmonyOS 真机尚未完成 mDNS/WebSocket/PasteButton 联合验收；模拟器结果不能关闭 H1。
- [ ] 模拟器发现目前依赖用户环境中的 VPN TUN；需要真机确认这是纯虚拟网络现象，而非桌面发布地址选择错误。
- [ ] `mdns-sd` 的自动地址枚举会包含哪些 Windows 虚拟接口尚未形成可重复测试；正式过滤规则应基于实际接口/地址观测，不按名称猜测。
- [ ] Windows 防火墙 UDP 5353 与动态 WebSocket TCP 端口的专用/公用网络行为仍需人工验证。
- [ ] 历史签名配置风险仍由用户决定是否只轮换材料或进一步处理远端历史；不要在后续文档中复述任何受保护内容。

## Deferred Items

- 正式 mDNS browse、最近地址回退、ConnectionManager、心跳和重连属于 D4，当前只有为 H1 提供的最小发布。
- 正式配对、设备身份、邀请、会话加密和防重放属于 D3/H3-H5，不能在 POC 帧里零散加入。
- SQLite/RDB、历史、retention 和 sync heads 属于 D2/H2。
- 认证 `ITEM_LIVE` 自动写入 Windows 剪贴板要等正式协议入口；`ITEM_BATCH` 永远不能触发系统剪贴板写入。

## Important Context

EggClip v1 是纯局域网文本剪贴板同步，不做账号、云端或公网中继。当前 `clipboardText` WebSocket JSON 是未认证、未加密的 POC，只能在可信开发网络使用；收到内容后桌面和 HarmonyOS 都依赖用户动作复制，不能为了展示效果开启自动写入。mDNS 也不是认证。桌面发布使用完整 `_eggclip._tcp.local.`，Harmony NetworkKit 查询必须使用 `_eggclip._tcp`；不要把这两个常量重新合并。用户已确认模拟器在开启 VPN TUN 时可以发现服务，但该条件只说明虚拟网络路由发生变化，下一代理必须优先做真机无 VPN 验收，而不是把 VPN 写成使用要求。

## Assumptions Made

- `d6ac742` 已包含本轮全部业务修改并与 `origin/main` 对齐。
- 用户没有要求创建分支、再次提交、推送或发布安装包。
- Windows 是桌面 v1 唯一承诺平台，mDNS POC 目前只需要 IPv4。
- HarmonyOS 继续以 SDK 6.1.1(24)、compatible 6.1.0(23) 为目标。
- 模拟器的 TUN 依赖属于环境现象，是否需要代码级接口过滤等待真机和地址观测后决定。

## Potential Gotchas

- 错误码 `0` 是 `MdnsError.INTERNAL_ERROR`，不是“无错误”。当前 UI 已给出模拟器组播和手动 IP 提示。
- UI 显示 `_eggclip._tcp.local.` 是正确的完整 DNS-SD 名称；传给 `createDiscoveryService` 的却必须是 `_eggclip._tcp`。
- `ServiceInfo::enable_addr_auto()` 方便 POC，但可能把 TUN/VPN 地址一起发布；发现成功不代表候选地址可从真机访问。
- 模拟器通过 TUN 发现成功不等于真实局域网 mDNS 验收通过。
- `harmony/build-profile.json5` 是本机签名相关边界，不要输出或提交本机材料。
- Harmony 构建仍会对 Pasteboard 读取给出权限静态警告；实际产品路径必须继续由真实 PasteButton 用户授权触发。
- Tauri dev URL 必须保持 `127.0.0.1`，VPN 环境不要改回 `localhost`。

## Environment State

### Tools/Services Used

- PowerShell in `D:\Develop\eggclip`
- Node/pnpm、Rust/Cargo、Tauri 2、Svelte 5
- DevEco Studio JBR、SDK 6.1.1(24) 和 Hvigor
- Local SDK definition: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.net.mdns.d.ts`
- `session-handoff` scripts with `PYTHONUTF8=1`

### Active Processes

- 生成 handoff 时未发现需要接管的 `eggclip.exe` 或 Cargo dev 进程。
- 未启动新的长期 dev server、mDNS 诊断进程或 Hvigor daemon。

### Environment Variables

- `JAVA_HOME`
- `DEVECO_SDK_HOME`
- `Path`
- `PYTHONUTF8`

## Validation Snapshot

本轮最后一次完整自动化验证：

- `pnpm check` passed，0 errors / 0 warnings
- `pnpm test` passed，2 tests
- `pnpm build` passed
- `cargo fmt -- --check` passed
- `cargo check` passed
- `cargo test` passed，14 tests
- HarmonyOS `hvigorw.bat test --no-daemon` passed
- HarmonyOS `hvigorw.bat assembleHap --no-daemon` passed
- `git diff --check` passed，仅有 Windows CRLF 提示
- Harmony 构建仍有预期的 Pasteboard 权限静态警告和共享配置未签名警告

当前 Git 状态：

- Branch: `main`
- HEAD and upstream: `d6ac742`, `main...origin/main`
- Untracked: `.claude/handoffs/2026-06-21-122354-eggclip-mdns-poc-and-emulator-findings.md`
- No staged or unstaged business-code changes

## Related Resources

- `AGENTS.md`
- `README.md`
- `DESKTOP_DEVELOPMENT_TODO.md`
- `HARMONY_DEVELOPMENT_TODO.md`
- `docs/EggClip最佳实现方案.md`
- `docs/MANUAL_REGRESSION.md`
- `desktop/README.md`
- `desktop/src-tauri/src/discovery/mod.rs`
- `desktop/src-tauri/src/clipboard/mod.rs`
- `harmony/entry/src/main/ets/services/discovery/MdnsDiscoveryService.ets`
- `harmony/entry/src/main/ets/pages/HomePage.ets`
- `.claude/handoffs/2026-06-21-104915-eggclip-h1-d1-poc-stabilized.md`

---

Security reminder: rerun the handoff validator after any edit and do not add runtime secrets, signing material, real clipboard samples, invitations, keys, digests, or complete network frames.
