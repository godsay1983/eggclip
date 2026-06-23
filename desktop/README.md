# EggClip Desktop

EggClip 桌面端是基于 Tauri 2、Svelte 5 和 Rust 的 Windows 托盘应用。当前 D1 POC 已实现 Windows 文本剪贴板监听、WebSocket server/手动客户端、最小 mDNS 服务发布、Desktop ↔ Desktop/HarmonyOS 双向手动文本传输，以及 sequence/digest/TTL 回环抑制基础。当前链路仍是未认证的临时明文 POC，不能视为正式同步协议。

## 开发

```powershell
pnpm install
pnpm tauri dev
```

应用启动后默认隐藏，请从系统托盘打开“蛋定 Clip”。

启动 POC server 后，桌面端会发布 `_eggclip._tcp.local.` 临时服务，并在状态卡中列出可用 IPv4、所属网卡及隧道标记；HarmonyOS 或另一桌面实例可使用这些地址和面板端口手动连接。桌面端在“连接另一桌面 POC”区域输入对端 IPv4 和端口即可建立出站连接，设备区域会显示当前 POC peer。两端正文上限为 256 KiB，1 MiB 只作为临时外层帧保护。未认证 POC 不自动广播或写入系统剪贴板：桌面发送需要点击面板操作，收到远端文本后也需要用户点击复制。

桌面监听会跳过带有 `ExcludeClipboardContentFromMonitorProcessing` 或 `CanUploadToCloudClipboard=0` 的来源内容。EggClip 写入系统剪贴板时设置 `CanUploadToCloudClipboard=0`，阻止 Windows 将内容上传到云剪贴板，同时不主动排除本机剪贴板历史。格式语义以 [Microsoft Clipboard Formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats#cloud-clipboard-and-clipboard-history-formats) 为准。

## 检查

```powershell
pnpm check
pnpm test
pnpm build
cd src-tauri
cargo fmt -- --check
cargo check
cargo test
```

完整计划见根目录 `DESKTOP_DEVELOPMENT_TODO.md`，架构决策见 `docs/EggClip最佳实现方案.md`。
