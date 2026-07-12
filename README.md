# EggClip（蛋定 Clip）

EggClip 是纯局域网剪贴板同步工具。Windows 桌面端负责自动监听和同步，HarmonyOS 端在前台连接，并通过系统授权操作发送或复制文本。

当前已完成局域网邀请配对、应用层认证加密、可信自动重连、纯文本实时同步、历史加密存储和断线补同步。桌面端托盘显示在线设备数并支持暂停/恢复同步；HarmonyOS 使用 PasteButton 发送，网络失败时记录进入待同步状态，连接恢复后自动补发并等待桌面端 `ITEM_ACK`。未认证 POC 仅保留为诊断入口。

最后核对：2026-07-12。

## v1 范围

- Windows 桌面端：开机启动、托盘常驻、自动发现、自动连接和文本自动同步。
- HarmonyOS 手机/平板：前台发现和连接、接收历史、用户点击复制、使用系统 `PasteButton` 发送。
- 仅支持 `text/plain`，单条最大 256 KiB。
- 默认保存最近 50 条且最长 7 天。
- 不使用账号、中心服务器、S3 或公网中继。

## 仓库结构

```text
eggclip/
├─ desktop/                         # Tauri 2 + Svelte 5 + Rust
├─ harmony/                         # HarmonyOS 6 ArkTS/ArkUI
├─ protocol/                        # v1 协议 schema、说明和测试向量
├─ docs/
│  ├─ EggClip最佳实现方案.md
│  └─ icon.png
├─ AGENTS.md
├─ DESKTOP_DEVELOPMENT_TODO.md
└─ HARMONY_DEVELOPMENT_TODO.md
```

## 开发环境

桌面端：

- Node.js 20 或更高版本
- pnpm 10 或更高版本
- Rust stable 1.85 或更高版本
- Windows WebView2 和 Tauri Windows 构建依赖

HarmonyOS 端：

- DevEco Studio
- HarmonyOS SDK `6.1.1(24)`
- JBR、Hvigor
- phone/tablet 模拟器；mDNS、PasteButton 和网络互通最终需要真机

## 桌面端

```powershell
cd D:\Develop\eggclip\desktop
pnpm install
pnpm tauri dev
```

应用启动后默认隐藏，通过系统托盘打开“蛋定 Clip”。

完整检查：

```powershell
pnpm release:check
```

生成 Windows NSIS 内部验收包：

```powershell
pnpm release:bundle
```

发布包生成后，额外指定实际包路径检查归档内是否混入调试产物：

```powershell
.\scripts\release-safety-check.ps1 -PackagePaths <发布包路径>
```

## HarmonyOS 端

使用 DevEco Studio 打开：

```text
D:\Develop\eggclip\harmony
```

命令行检查：

```powershell
cd D:\Develop\eggclip\harmony
$env:JAVA_HOME = 'C:\Program Files\Huawei\DevEco Studio\jbr'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' test --no-daemon
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon
```

共享的 `build-profile.json5` 不包含签名材料，因此命令行默认生成未签名 HAP。正式真机或发布构建应在本机/CI 注入签名配置，证书和密码不得提交。

## 当前验证结果

- 桌面：Svelte 类型检查、Vitest、前端构建、Rust fmt/check/test 通过；Rust 共 130 个测试通过。
- 桌面：托盘菜单已接入在线数、暂停/恢复、设备管理入口和动态 tooltip，完整交互仍需 Windows 人工回归。
- HarmonyOS：同步、连接管理、stores、首页状态策略和跨端协议向量自动化测试已通过 `hvigorw test`，当前产物未签名。
- 桌面 POC server 启动时会发布 `_eggclip._tcp.local.` 临时服务；mDNS 只提供候选地址，不代表设备可信。
- 当前手动回归清单包含 Windows 剪贴板隐私标记样本工具和 POC WebSocket 帧探针脚本，D1/H1 手动验收已通过。
- 已创建 `protocol/README.md`、`protocol/v1.schema.json` 和初始 schema/解析测试向量目录；桌面 Rust 与 HarmonyOS ArkTS 已接入协议类型和 fixture 测试，密码学字节级向量仍待补齐。
- 当前工作树未发现签名密码、证书路径或剪贴板正文。

## 开发顺序

1. 补齐 `protocol/test-vectors/` 中的密码学字节级向量。
2. 实现设备身份、本地密钥保存、配对和端到端加密握手。
3. 实现本地历史、sync heads、`ITEM_LIVE` / `ITEM_BATCH` 分流和 retention。
4. 实现自动发现、补同步、设备管理和发布回归。

## 相关文档

- [开发约定](AGENTS.md)
- [最佳实现方案](docs/EggClip最佳实现方案.md)
- [隐私说明](docs/PRIVACY.md)
- [局域网连接排障](docs/LAN_TROUBLESHOOTING.md)
- [发布、升级与回滚清单](docs/RELEASE.md)
- [双端 UI 精简改造 Roadmap](docs/UI_REFINEMENT_ROADMAP.md)
- [桌面端开发计划](DESKTOP_DEVELOPMENT_TODO.md)
- [HarmonyOS 开发计划](HARMONY_DEVELOPMENT_TODO.md)

## 安全提示

- 不要提交 `build-profile.json5` 中的签名 `material`、证书、私钥或密码。
- 不要把真实剪贴板内容、邀请秘密、密钥或摘要写入日志和测试快照。
- 历史提交 `74d9bb1` 曾包含本机签名配置，使用相关材料前应完成轮换，并评估是否重写远端 Git 历史。
