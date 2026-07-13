# EggClip 隐私数据清单

更新日期：2026 年 7 月 13 日

本清单以当前 Windows 和 HarmonyOS 实现为准，用于核对应用内隐私说明、公开隐私政策及
AppGallery Connect 隐私标签。它不是新增功能清单。

控制台逐项填写方式见 `docs/APPGALLERY_PRIVACY_LABEL_CHECKLIST.md`。

| 数据 | 来源 | 用途 | 存放或接收方 | 保存和用户控制 |
| --- | --- | --- | --- | --- |
| 剪贴板纯文本 | Windows 新复制文本；HarmonyOS 用户点击系统安全粘贴按钮 | 实时同步和本机历史 | 本机加密历史；用户选择的已配对局域网设备 | 单条最大 256 KiB；默认 50 条、7 天；可关闭或清空历史 |
| 设备 ID、显示名称 | 应用生成；用户可重命名 | 标识本机和可信设备 | 本机 RDB；配对设备会获得必要的设备 ID | 移除设备、重置配对或清除应用数据时删除 |
| 身份公钥、可信状态 | 配对和身份认证 | 校验设备身份、可信重连和撤销 | 本机 RDB；身份公钥与配对设备交换 | 移除设备后进入撤销流程并轮换空间密钥 |
| 设备私钥 | 应用生成 | Ed25519 身份签名 | Windows 系统凭据库或 HarmonyOS HUKS，不离开本机 | 清除相应安全存储或应用数据时删除 |
| 同步空间密钥 | 配对安全通道接收或生成 | 历史加密、消息认证和空间密钥轮换 | Windows 系统凭据库或 HarmonyOS HUKS；RDB 仅保存引用 | 移除设备轮换；重新初始化安全状态时删除 |
| IP 地址、端口、发现结果 | 局域网 mDNS、邀请候选地址或用户输入 | 前台发现、连接、可信重连和诊断 | 最近可信地址保存在本机；候选发现结果仅用于前台会话 | 重置配对、清除应用数据或被新地址替换时删除 |
| 加密历史及同步元数据 | 本地或远端剪贴板事件 | 最近记录、去重、排序和离线补齐 | 本机 RDB；正文为 AES-GCM 加密内容，摘要为 HMAC | 遵循历史开关、数量和天数；可手动清空 |
| 应用设置 | 用户选择 | 控制同步、接收、历史、保留策略和主题 | 本机 RDB | 用户修改或清除应用数据时更新或删除 |
| 运行日志和诊断状态 | 应用生命周期、连接及错误处理 | 本机排障 | 本机系统日志或当前诊断界面 | 不包含正文、邀请秘密、密钥、完整摘要或完整帧 |

## 权限与网络核对

- HarmonyOS 仅声明 `ohos.permission.INTERNET` 和 `ohos.permission.GET_NETWORK_INFO`。
- HarmonyOS 剪贴板读取由系统 `PasteButton` 一次性授权，不声明后台静默读取权限。
- 网络连接目标是用户局域网中的桌面端或其他已配对设备，不存在开发者中心服务器或公网中继。
- 当前工程未集成广告、营销、统计分析、跨应用跟踪或第三方崩溃上报 SDK。

## 代码事实来源

- 权限：`harmony/entry/src/main/module.json5`
- 剪贴板授权：`harmony/entry/src/main/ets/services/clipboard/ClipboardBridgeService.ets`
- RDB schema：`harmony/entry/src/main/ets/data/migrations/SchemaMigrations.ets`
- 本机历史加密：`harmony/entry/src/main/ets/services/sync/InboundItemLiveService.ets` 和
  `OutboundItemLiveService.ets`
- HUKS 密钥：`harmony/entry/src/main/ets/services/crypto/Ed25519HuksIdentityService.ets` 和
  `SpaceKeyHuksService.ets`
- 最近可信地址：`harmony/entry/src/main/ets/data/repositories/RdbRepositories.ets`
