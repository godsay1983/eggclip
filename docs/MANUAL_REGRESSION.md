# EggClip 手动回归清单

本文记录当前 D1/H1 POC 的真机验证项。测试时不要保存或截图真实敏感剪贴板内容，使用无敏感信息的固定样例。

## 当前前提

- Windows 与 HarmonyOS 设备位于同一可信 Wi-Fi。
- Windows 防火墙允许 EggClip 在专用网络监听。
- 当前 WebSocket POC 是未认证、未加密的临时链路，只用于开发网络。
- 桌面 POC server 会发布 `_eggclip._tcp.local.` 临时服务；mDNS 只用于候选地址发现，不代表设备可信。

## Desktop ↔ HarmonyOS POC

- [ ] 在“设置 → 常规”开启开机自动启动，重新登录 Windows 后确认 EggClip 仅进入托盘且不弹出主面板；关闭后再次登录，确认不再自动启动。

- [x] 桌面端启动后从托盘打开面板，确认 POC server 显示监听端口。
- [x] 桌面状态卡列出 WLAN/以太网 IPv4；TUN/VPN 地址有“隧道”标记，不把该标记当成真机首选地址。
- [x] HarmonyOS 输入 Windows 局域网 IPv4 和端口后连接成功。
- [x] HarmonyOS 连接后，桌面设备区域显示对应 POC peer；断开后状态同步移除。
- [x] HarmonyOS 顶部状态卡正确区分发现中、发现失败、已发现候选、连接中、在线和离线。
- [x] HarmonyOS 点击真实 PasteButton，发送中文、Emoji 和多行测试文本；Windows 面板显示预览，但未认证 POC 不自动写入系统剪贴板。
- [x] Windows 用户点击复制后内容写入本机剪贴板，且不会自动向未认证 peer 广播。
- [x] Windows 本机复制测试文本后，在面板点击发送，HarmonyOS 显示最新收到内容，但不会自动写入手机剪贴板。
- [x] HarmonyOS 点击“复制到本机”后，目标文本才写入手机剪贴板。
- [x] 断开 HarmonyOS 后，Windows 本地复制不受影响。

## 回环与边界

- [x] 在 Windows 连续复制相同文本两次，确认两次本机动作都可被识别。
- [x] 接入认证 `ITEM_LIVE` 后，验证远端写入回调被 suppression token 消耗一次，稍后的相同文本手动复制仍可识别。
- [x] 验证空文本、256 KiB、超过 256 KiB、中文、Emoji 和多行文本。
- [x] 连续双向复制 100 次，无无限回环、重复风暴或明显卡顿。

## 认证连接初始化

- [ ] 桌面端已启动时，同时让手机和平板恢复可信连接；两端均显示“已就绪”后，不先从电脑发送，分别使用 PasteButton 向 Windows 发送固定测试文本，确认桌面立即收到。
- [ ] 在鸿蒙端刚显示“初始化中”时触发一次 PasteButton，确认界面显示等待初始化，并在变为“已就绪”后自动提交，不误报“网络不可用”。
- [ ] 初始化完成后验证 Windows → 手机/平板和手机/平板 → Windows 均可独立首发，且没有同步回环。

## Windows ↔ Windows 可信重连

- [ ] Windows B 通过邀请加入 Windows A 后，关闭并重新打开 B；确认无需再次粘贴邀请即可恢复同一可信设备会话。
- [ ] 修改 Windows A 的局域网地址或切换两台电脑的网络，等待 mDNS 更新；确认 B 优先连接与已保存设备 ID 完全匹配的新地址。
- [ ] 临时阻断新地址的连接，确认 B 会回退到上次认证成功地址，并且设备状态不会在“连接中/认证失败”之间快速闪烁。
- [ ] 保持两端空间密钥版本一致重连，确认不重复下发密钥；让 B 落后一个版本后重连，确认接收新密钥；模拟 B 声称版本超前时确认连接被拒绝。

## Windows 剪贴板隐私标记

辅助命令：

```powershell
cd D:\Develop\eggclip\desktop\src-tauri
cargo run --bin clipboard_marker_sample -- exclude-monitoring
cargo run --bin clipboard_marker_sample -- cloud-deny
cargo run --bin clipboard_marker_sample -- inspect
```

验证方式：保持桌面端运行并打开面板，分别写入样本后确认“当前剪贴板”不会更新为新的本机同步候选；`inspect` 只输出标记状态，不输出剪贴板正文。

- [x] 使用测试工具写入 `ExcludeClipboardContentFromMonitorProcessing` 后，EggClip 不产生本机同步候选。
- [x] 使用测试工具写入 `CanUploadToCloudClipboard=0` 后，EggClip 不产生本机同步候选。
- [x] 通过 EggClip 复制文本后，确认 `CanUploadToCloudClipboard` 为 0，文本仍可在本机剪贴板使用。
- [x] 上述排除路径不输出正文或标记原始数据到普通日志。

## POC 安全帧诊断

辅助命令：

```powershell
cd D:\Develop\eggclip\desktop
.\scripts\poc-frame-probe.ps1 -HostName 127.0.0.1 -Port <桌面面板显示的 POC 端口> -Case all
```

验证方式：运行前记录面板中的“帧诊断”计数。`all` 会为每种样本各建立一次 WebSocket 连接；正常文本应增加接收/接受，非法 JSON、空文本、超限正文和二进制帧应增加接收/拒绝。不要把真实剪贴板内容放进探针样本。

- [x] 正常文本到达时，两端“接收”和“接受”各增加 1，“拒绝”不变。
- [x] 非法 JSON、空文本、超限正文或二进制帧只增加“接收/拒绝”，不进入最新文本预览。
- [x] 重新建立 POC 会话后诊断计数归零。
- [x] 诊断页面和普通日志不显示正文、摘要或完整网络帧。

## HarmonyOS 生命周期与发现

- [x] App 在前台时可开始/停止 `_eggclip._tcp.local.` 搜索。
- [x] 重复发现回调不会生成重复候选地址。
- [x] 候选只显示 IPv4、端口和协议版本，不显示未允许的 TXT 内容。
- [x] App 进入后台后停止 mDNS 并断开 WebSocket；回到前台后恢复搜索，并在之前已连接时尝试重连。
- [x] 在正常 Wi-Fi、访客网络和启用 AP 隔离的网络分别记录发现结果。

## HarmonyOS 浮动底部导航

- [ ] 分别在 phone、tablet 和折叠屏展开态打开首页、设备页和设置页，确认正文不会被浮动导航遮挡。
- [ ] 将系统字体调大，在最近记录、未配对帮助、连接诊断和设置长内容下滚动到底，确认最后一项可以完整停在导航栏上方。
- [ ] 在三个页签间连续切换并滚动，确认正文不跳动，页面底部没有异常大块空白。
