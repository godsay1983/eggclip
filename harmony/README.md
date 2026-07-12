# EggClip HarmonyOS

DevEco Studio 工程根目录。目标 SDK 为 `6.1.1(24)`。

## 统一验证

在 PowerShell 中运行：

```powershell
cd D:\Develop\eggclip\harmony
.\scripts\verify.ps1
```

该命令依次执行 ArkTS 格式检查、DevEco Code Linter、单元测试、ArkTS 类型检查和 HAP 构建。

单独运行：

```powershell
.\scripts\format-arkts.ps1
.\scripts\format-arkts.ps1 -Fix
.\scripts\lint-arkts.ps1
.\scripts\test.ps1
```

脚本默认使用 `C:\Program Files\Huawei\DevEco Studio`，也可以通过 `-DevEcoHome` 指定安装目录。

## Release 内部检查包

在仓库根目录运行：

```powershell
.\scripts\build-harmony-release.ps1
```

共享构建配置不包含签名材料，因此脚本生成未签名 HAP，仅用于自动化和发布前检查。正式包必须通过 DevEco Studio 本机配置或 CI secret 注入签名。应用数据备份保持关闭，避免 RDB 中的 HUKS 引用与设备安全存储分离恢复。正式签名、覆盖升级和回滚步骤见根目录 `docs/RELEASE.md`。

## 密钥诊断与恢复

设置页可以运行 HUKS 空间密钥加解密与 HMAC 自检。密钥引用缺失时会提示重新配对；引用存在但 HUKS 运算失败时，可以使用“重新初始化配对安全状态”。该操作会先删除对应的 HUKS AES/HMAC 密钥，再事务清理同步空间、可信设备、同步历史和最近可信地址，保留应用设置与本机 Ed25519 长期身份。恢复完成后必须重新扫码或粘贴邀请配对。

桌面端移除任一可信设备后会轮换空间密钥。鸿蒙端只接受同一空间中版本严格递增的 `rotation-v1` 密钥包，并在同一 RDB 事务中清空旧密钥绑定的同步历史、同步头并切换密钥引用；旧版本、其他空间或错误交付类型都会被拒绝。
