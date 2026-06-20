# EggClip（蛋定 Clip）

EggClip 是纯局域网剪贴板同步工具。Windows 桌面端负责自动监听和同步，HarmonyOS 端在前台连接，并通过系统授权操作发送或复制文本。

当前处于工程基线阶段：两端空壳、主题和构建链路已建立，剪贴板监听、mDNS、WebSocket、配对与端到端加密尚未进入实现。

最后核对：2026-06-20。

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

- 桌面：Svelte 类型检查、Vitest、前端构建、Rust fmt/check/test 通过。
- 桌面：Tauri dev 进程、Vite 服务和 `eggclip.exe` 已成功启动；托盘交互仍需人工回归。
- HarmonyOS：单元测试和 `assembleHap` 通过，当前产物未签名。
- 当前工作树未发现签名密码、证书路径或剪贴板正文。

## 开发顺序

1. 完成两端 H0/D0 人工回归和签名处理。
2. 验证 Windows 原生剪贴板事件和手动 WebSocket。
3. 验证 HarmonyOS 真机 mDNS、WebSocket、PasteButton 和 Pasteboard 写入。
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
