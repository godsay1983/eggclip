# EggClip 手动回归清单

本文记录当前 D1/H1 POC 的真机验证项。测试时不要保存或截图真实敏感剪贴板内容，使用无敏感信息的固定样例。

## 当前前提

- Windows 与 HarmonyOS 设备位于同一可信 Wi-Fi。
- Windows 防火墙允许 EggClip 在专用网络监听。
- 当前 WebSocket POC 是未认证、未加密的临时链路，只用于开发网络。
- 桌面 POC server 会发布 `_eggclip._tcp.local.` 临时服务；mDNS 只用于候选地址发现，不代表设备可信。

## Desktop ↔ HarmonyOS POC

- [ ] 桌面端启动后从托盘打开面板，确认 POC server 显示监听端口。
- [ ] HarmonyOS 输入 Windows 局域网 IPv4 和端口后连接成功。
- [ ] HarmonyOS 点击真实 PasteButton，发送中文、Emoji 和多行测试文本；Windows 面板显示预览，但未认证 POC 不自动写入系统剪贴板。
- [ ] Windows 用户点击复制后内容写入本机剪贴板，且不会自动向未认证 peer 广播。
- [ ] Windows 本机复制测试文本后，在面板点击发送，HarmonyOS 显示最新收到内容，但不会自动写入手机剪贴板。
- [ ] HarmonyOS 点击“复制到本机”后，目标文本才写入手机剪贴板。
- [ ] 断开 HarmonyOS 后，Windows 本地复制不受影响。

## 回环与边界

- [ ] 在 Windows 连续复制相同文本两次，确认两次本机动作都可被识别。
- [ ] 接入认证 `ITEM_LIVE` 后，验证远端写入回调被 suppression token 消耗一次，稍后的相同文本手动复制仍可识别。
- [ ] 验证空文本、256 KiB、超过 256 KiB、中文、Emoji 和多行文本。
- [ ] 连续双向复制 100 次，无无限回环、重复风暴或明显卡顿。

## HarmonyOS 生命周期与发现

- [ ] App 在前台时可开始/停止 `_eggclip._tcp.local.` 搜索。
- [ ] 重复发现回调不会生成重复候选地址。
- [ ] 候选只显示 IPv4、端口和协议版本，不显示未允许的 TXT 内容。
- [ ] App 进入后台后停止 mDNS 并断开 WebSocket；回到前台后恢复搜索，并在之前已连接时尝试重连。
- [ ] 在正常 Wi-Fi、访客网络和启用 AP 隔离的网络分别记录发现结果。
