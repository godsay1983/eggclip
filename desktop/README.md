# EggClip Desktop

EggClip 桌面端是基于 Tauri 2、Svelte 5 和 Rust 的 Windows 托盘应用。当前已实现 Windows 文本剪贴板监听、认证 WebSocket 同步、协议 v1 mDNS 发布/浏览、邀请配对、可信重连和断线补同步；未认证 POC 只保留为手动诊断入口，不能视为正式同步协议。

## 开发

```powershell
pnpm install
pnpm tauri dev
```

应用启动后默认隐藏，请从系统托盘打开“蛋定 Clip”。托盘菜单会显示正式认证设备在线数，可直接暂停/恢复同步，并可打开面板后定位到设备管理；tooltip 同步显示当前同步开关和在线设备数。

“设置 → 常规 → 开机自动启动”直接读取和修改 Windows 的实际启动项状态。开启后，用户登录 Windows 时 EggClip 会携带 `--autostart` 参数在后台进入托盘，不主动弹出主面板；该状态由系统管理，不写入剪贴板设置数据库。

启动同步监听后，桌面端会发布 `_eggclip._tcp.local.` 协议 v1 服务，并同时浏览其他 EggClip 服务。TXT 只包含稳定设备 ID、协议版本、传输类型和能力，不包含设备名称、正文、邀请或密钥。诊断卡列出可用 IPv4、所属网卡、隧道标记和浏览结果；HarmonyOS 会优先使用与可信设备 ID 匹配的 mDNS 地址，解析不到时回退到最近一次认证成功的地址，用户仍可使用诊断卡显示的 IPv4 和端口手动排障。作为空间成员加入另一台 Windows 后，桌面端只会为已保存的协调端创建主动重连任务；当前 mDNS 地址优先，上次认证成功地址作为回退，网络或地址变化后按带抖动退避自动恢复连接。

两端正文上限为 256 KiB，1 MiB 只作为临时外层帧保护。未认证 POC 不自动广播或写入系统剪贴板：桌面发送需要点击面板操作，收到远端文本后也需要用户点击复制。

桌面端收到 HarmonyOS 的认证 `ITEM_LIVE` 后，会按设置写入 Windows 剪贴板，并立即刷新首页预览和历史列表，无需再点击“读取本机剪贴板”；远端写入仍受回环抑制，不会再次发送回 HarmonyOS。桌面端会对成功持久化的 `ITEM_LIVE` 返回加密 `ITEM_ACK`。HarmonyOS 在网络失败时保留正式同步记录，重连后通过 `SYNC_HEADS`、范围请求和 `ITEM_BATCH` 自动补发，直到收到桌面端确认。

两台 Windows 建立正式可信会话后，系统剪贴板监听会把本机复制自动发送到同一空间的服务端方向或客户端方向会话，不需要点击手动发送。接收端按“同步”“自动接收”和“自动写入”设置处理 `ITEM_LIVE`；远端写入使用一次性回环抑制标记，相同文本稍后由用户再次复制仍会作为新的本机操作。关闭历史不会阻止实时接收和确认，关闭同步或自动接收则不会写入、展示或确认该实时事件。

生成配对邀请后，可点击二维码下方的“放大扫码”，在当前桌面面板内显示更大的二维码；点击背景、关闭按钮或按 `Esc` 均可返回设置页。

手动连接卡片显示当前会话接收、接受、拒绝帧数和上次拒绝类型。诊断不包含剪贴板正文、摘要或完整网络帧。

设置中的可信设备卡片显示数据库记录和认证会话状态，可重命名或移除设备。移除会立即撤销该设备、关闭其连接并把空间密钥提升一个版本；仍受信任的在线设备会通过加密会话收到新密钥，离线设备在下次可信重连时补领。v1 的历史正文和摘要绑定空间密钥，因此轮换时会清空该同步空间两端的本地同步历史，确认框会明确提示这一点。

可信重连会在签名握手上下文中携带客户端当前空间密钥版本。版本相同时桌面端不重复下发密钥，以首轮 `SYNC_HEADS` 作为同步就绪信号；客户端版本落后时才下发严格递增的 `rotation-v1` 密钥包，客户端声称的版本高于桌面端时拒绝连接。

同步空间列表只展示带系统凭据密钥的正式空间，不展示内部“本机历史”容器。空间卡片支持删除；仍有可信设备或认证会话在线的空间会拒绝删除，并且始终至少保留一个正式同步空间。删除当前空间时会自动选择另一个保留空间。

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

## NSIS 内部验收包

```powershell
pnpm release:bundle
```

该命令先执行完整检查和统一版本门禁，再生成仅面向 Windows 的当前用户 NSIS 安装器，并检查发布目录是否混入调试产物。未配置受信任代码签名证书时只可用于内部验收；正式发布、覆盖升级、卸载和回滚步骤见根目录 `docs/RELEASE.md`。

完整计划见根目录 `DESKTOP_DEVELOPMENT_TODO.md`，架构决策见 `docs/EggClip最佳实现方案.md`。
