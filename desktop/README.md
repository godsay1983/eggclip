# EggClip Desktop

EggClip 桌面端是基于 Tauri 2、Svelte 5 和 Rust 的 Windows 托盘应用。当前已实现 Windows 文本剪贴板监听、认证 WebSocket 同步、协议 v1 mDNS 发布/浏览、邀请配对、可信重连和断线补同步；未认证 POC 只保留为手动诊断入口，不能视为正式同步协议。

## 开发

```powershell
pnpm install
pnpm tauri dev
```

应用启动后默认隐藏，请从系统托盘打开“蛋定 Clip”。

启动同步监听后，桌面端会发布 `_eggclip._tcp.local.` 协议 v1 服务，并同时浏览其他 EggClip 服务。TXT 只包含稳定设备 ID、协议版本、传输类型和能力，不包含设备名称、正文、邀请或密钥。诊断卡列出可用 IPv4、所属网卡、隧道标记和浏览结果；HarmonyOS 会优先使用与可信设备 ID 匹配的 mDNS 地址，解析不到时回退到最近一次认证成功的地址，用户仍可使用诊断卡显示的 IPv4 和端口手动排障。

两端正文上限为 256 KiB，1 MiB 只作为临时外层帧保护。未认证 POC 不自动广播或写入系统剪贴板：桌面发送需要点击面板操作，收到远端文本后也需要用户点击复制。

手动连接卡片显示当前会话接收、接受、拒绝帧数和上次拒绝类型。诊断不包含剪贴板正文、摘要或完整网络帧。

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
