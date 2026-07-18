# EggClip 应用商店中英文资料

本文用于 Windows 分发页和 AppGallery Connect 的简体中文、英语语言条目。实际提交时应分别填写对应语言，不要把两种语言合并到同一字段。若商店字符限制发生变化，以控制台即时校验为准。

## 简体中文

应用名称：`EggClip`

一句话简介：`纯局域网跨设备剪贴板同步`

应用介绍：

> EggClip 是一款纯局域网剪贴板同步工具，帮助 Windows 电脑与 HarmonyOS 手机、平板，以及多台 Windows 电脑之间安全同步文本。
>
> 在同一局域网中完成一次邀请配对后，Windows 端可自动监听和同步文本剪贴板。HarmonyOS 端遵循系统剪贴板授权规则：发送文本时由用户点击系统 PasteButton，接收文本后由用户主动复制到本机剪贴板。可信设备可在应用重启后自动重连，并在网络恢复后补齐遗漏的历史记录。
>
> EggClip 不需要账号，不依赖中心服务器、公网中继或云存储。设备发现只用于寻找局域网地址，正式同步使用设备身份认证和应用层加密。应用仅支持纯文本，单条内容最大 256 KiB。
>
> 主要功能：Windows 与 HarmonyOS 双向文本同步；多台 Windows 电脑互联；手机和平板适配；可信设备管理和空间密钥轮换；最近记录和断线补同步；简体中文、English 与跟随系统；浅色、深色和跟随系统主题。
>
> 使用前请在 Windows 电脑安装并运行 EggClip，确保设备连接同一可信局域网。访客网络、AP 隔离、防火墙或 VPN/TUN 配置可能阻止设备互相访问。

截图文案：

1. `同一局域网，安全同步文本`
2. `电脑、手机和平板双向互通`
3. `可信重连，断线后自动补齐`

版本更新说明：

> 新增简体中文、English 和跟随系统语言；完善手机、平板与 Windows 的本地化界面、动态状态、错误提示和无障碍文案；程序生成名称可随本机语言显示，用户自定义名称保持不变。

## English

App name: `EggClip`

Short description: `Secure clipboard sync on your local network`

Full description:

> EggClip is a local-network clipboard sync app for Windows PCs, HarmonyOS phones and tablets, and multiple Windows computers.
>
> After a one-time invitation pairing on the same local network, the Windows app can monitor and sync text automatically. The HarmonyOS app follows system clipboard authorization rules: you send text by tapping the system PasteButton and copy received text to the device with an explicit action. Trusted devices reconnect after restart and fill missing history when the network becomes available again.
>
> EggClip requires no account and uses no central server, public relay, or cloud storage. Discovery only locates devices on the LAN. Trusted synchronization uses device authentication and application-layer encryption. EggClip supports plain text up to 256 KiB per item.
>
> Highlights: two-way text sync between Windows and HarmonyOS; Windows-to-Windows sharing; phone and tablet layouts; trusted device management and space-key rotation; recent history and offline backfill; Simplified Chinese, English, and system language modes; light, dark, and system themes.
>
> Install and run EggClip on a Windows PC before pairing, and keep all devices on the same trusted local network. Guest Wi-Fi, AP isolation, firewalls, or VPN/TUN settings may prevent devices from reaching each other.

Screenshot captions:

1. `Secure text sync on your local network`
2. `Connect PCs, phones, and tablets`
3. `Trusted reconnect with offline backfill`

What's new:

> Added Simplified Chinese, English, and system language modes. Localized phone, tablet, and Windows interfaces, live status, errors, and accessibility text. Generated names now follow the local language while user-defined names remain unchanged.

## 提交前复核

- 中文和英文条目分别选择正确语言，名称保持 `EggClip`。
- 截图中的界面语言与对应商店条目一致，且不包含邀请秘密、IP、设备完整标识或真实剪贴板内容。
- 功能描述与候选包一致；HarmonyOS 不描述为后台静默读取剪贴板。
- 隐私政策、权限说明和隐私标签继续声明：无账号、无云同步、无广告/统计 SDK，语言偏好只保存在本机。
- 更新说明中的版本号由最终候选包元数据决定，不在本文提前写死。
