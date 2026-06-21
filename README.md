# EggClip（蛋定 Clip）

EggClip 是纯局域网剪贴板同步工具。Windows 桌面端负责自动监听和同步，HarmonyOS 端在前台连接，并通过系统授权操作发送或复制文本。

当前处于 D1/H1 技术 POC 阶段：Windows 剪贴板监听、双向 WebSocket 文本传输、桌面端手动 IP/端口出站连接、最小 mDNS 服务发布、局域网候选地址诊断和 POC peer 状态已接通；HarmonyOS 已接入真实 PasteButton、严格 IPv4 手动连接、前台 mDNS 搜索和动态连接状态。两端统一限制正文最大 256 KiB，外层 POC 帧最大 1 MiB。当前 POC 尚未认证，因此远端文本只进入预览，必须由用户点击复制；配对、端到端加密、历史存储和正式协议尚未实现。

最后核对：2026-06-21。

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
├─ protocol/                        # 后续建立：协议 schema 和测试向量
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

- 桌面：Svelte 类型检查、Vitest、前端构建、Rust fmt/check/test 通过；Rust 共 18 个测试通过。
- 桌面：Tauri dev 进程、Vite 服务和 `eggclip.exe` 已成功启动；托盘交互仍需人工回归。
- HarmonyOS：mDNS 搜索代码、WebSocket/PasteButton POC 以及 H1 边界单测已通过 `hvigorw test`，当前产物未签名。
- 桌面 POC server 启动时会发布 `_eggclip._tcp.local.` 临时服务；mDNS 只提供候选地址，不代表设备可信。
- 当前工作树未发现签名密码、证书路径或剪贴板正文。

## 开发顺序

1. 在 Windows 与 HarmonyOS 真机上回归当前双向手动传输链路和前后台行为。
2. 完成 H1 mDNS 发现与前后台生命周期的真机验证。
3. 使用桌面面板的手动 IPv4/端口连接补齐 D1 连续重复复制、防火墙和两台 Windows 互通测试。
4. 固化版本化协议、配对和端到端加密。
5. 实现自动发现、补同步、设备管理和发布回归。

## 相关文档

- [开发约定](AGENTS.md)
- [最佳实现方案](docs/EggClip最佳实现方案.md)
- [桌面端开发计划](DESKTOP_DEVELOPMENT_TODO.md)
- [HarmonyOS 开发计划](HARMONY_DEVELOPMENT_TODO.md)

## 安全提示

- 不要提交 `build-profile.json5` 中的签名 `material`、证书、私钥或密码。
- 不要把真实剪贴板内容、邀请秘密、密钥或摘要写入日志和测试快照。
- 历史提交 `74d9bb1` 曾包含本机签名配置，使用相关材料前应完成轮换，并评估是否重写远端 Git 历史。
