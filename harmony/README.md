# EggClip HarmonyOS

DevEco Studio 工程根目录。目标 SDK 为 `6.1.1(24)`。

## 统一验证

在 PowerShell 中运行：

```powershell
cd D:\Develop\eggclip\harmony
.\scripts\verify.ps1
```

该命令依次执行 ArkTS 格式检查、DevEco Code Linter、单元测试、ArkTS 类型检查和 HAP 构建。

## 语言设置

在“设置 → 外观 → 语言”中可选择“跟随系统”“简体中文”或“English”。EggClip 保存并回读确认应用首选语言后，会询问是否立即受控重启；页面、标题和底部导航会在运行时按该偏好读取资源，避免 Ability 重启后沿用旧进程语言缓存。三种模式都可以重复点击以重新应用。选择稍后或系统拒绝重启时，应从系统设置强行停止应用后重新打开；只从最近任务划掉应用不一定会终止缓存进程。“跟随系统”遇到非简体中文系统语言时回退为 English。

实际资源语言由 HarmonyOS 应用首选语言管理；EggClip 只在本机 Preferences 中额外保存“跟随系统/简体中文/English”三态选择，确保平台回报实际系统语言时仍能正确显示“跟随系统”。语言设置不写入 RDB，也不参与同步。程序生成的空间和设备名称会按本机语言显示，用户重命名的内容保持原文。手机和平板都需要在正式签名真机包上完成中文、英文和跟随系统冷启动回归。

单独运行：

```powershell
.\scripts\format-arkts.ps1
.\scripts\format-arkts.ps1 -Fix
.\scripts\lint-arkts.ps1
.\scripts\test.ps1
```

脚本默认使用 `C:\Program Files\Huawei\DevEco Studio`，也可以通过 `-DevEcoHome` 指定安装目录。

仓库级国际化资源检查：

```powershell
cd D:\Develop\eggclip
.\scripts\check-i18n.ps1
```

## Release 内部检查包

在仓库根目录运行：

```powershell
.\scripts\build-harmony-release.ps1
```

共享构建配置不包含签名材料，因此脚本生成未签名 HAP，仅用于自动化和发布前检查。正式包必须通过 DevEco Studio 本机配置或 CI secret 注入签名。应用数据备份保持关闭，避免 RDB 中的 HUKS 引用与设备安全存储分离恢复。正式签名、覆盖升级和回滚步骤见根目录 `docs/RELEASE.md`。

## 密钥诊断与恢复

设置页可以运行 HUKS 空间密钥加解密与 HMAC 自检。密钥引用缺失时会提示重新配对；引用存在但 HUKS 运算失败时，可以使用“重新初始化配对安全状态”。该操作会先删除对应的 HUKS AES/HMAC 密钥，再事务清理同步空间、可信设备、同步历史和最近可信地址，保留应用设置与本机 Ed25519 长期身份。恢复完成后必须重新扫码或粘贴邀请配对。

桌面端移除任一可信设备后会轮换空间密钥。鸿蒙端只接受同一空间中版本严格递增的 `rotation-v1` 密钥包，并在同一 RDB 事务中清空旧密钥绑定的同步历史、同步头并切换密钥引用；旧版本、其他空间或错误交付类型都会被拒绝。

可信连接把“身份已认证”和“同步已就绪”分开显示。收到 `AUTH_OK` 后仍会等待空间密钥处理和首轮 `SYNC_HEADS` 完成；这段时间通过 PasteButton 读取的文本会先加密保存，初始化完成后自动提交，不需要先由桌面端发送文本来激活反向同步。历史补同步异常不会再被误报为整个实时连接断开。

## 应用内评价

设置页底部提供“支持 EggClip”主动评价入口，优先使用 AppGallery Kit 的系统评论弹窗，平台接口不可用时再打开 EggClip 的应用市场写评论页。自动请求只在可信发送收到 `ITEM_ACK`，或用户把远端文本成功复制到系统剪贴板后检查；应用至少使用 7 天、活跃 3 天并跨过成功操作里程碑后才可能出现，同版本最多一次、90 天冷却且每年最多两次。评价频率状态只保存在本机 Preferences，不进入剪贴板历史、同步协议或备份。

系统评论弹窗不支持模拟器。模拟器只验证设置入口、主题、国际化和失败路径；真实弹窗必须在登录华为账号且 AppGallery 可用的 HarmonyOS 6.0.0(20) 以上真机验收。
