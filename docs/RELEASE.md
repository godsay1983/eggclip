# EggClip 发布与回滚清单

本文覆盖 Windows NSIS 和 HarmonyOS HAP 的内部验收、正式签名、升级、卸载与回滚。正式发布前必须先完成两个平台 TODO 中的真机回归。

## 统一版本与安全门禁

四个桌面/HarmonyOS 版本面必须保持一致：

- `desktop/package.json` 的 `version`。
- `desktop/src-tauri/Cargo.toml` 的 package `version`。
- `desktop/src-tauri/tauri.conf.json` 的 `version`。
- `harmony/AppScope/app.json5` 的 `versionName`；每次发布同时递增 `versionCode` 和 `buildVersion`。

执行：

```powershell
.\scripts\verify-release-metadata.ps1
.\scripts\release-safety-check.ps1
```

安全检查不得输出或提交签名密码、证书路径、剪贴板正文、邀请秘密和密钥。共享 `harmony/build-profile.json5` 必须保持无签名材料。

## Windows NSIS

内部验收包：

```powershell
cd D:\Develop\eggclip\desktop
pnpm release:bundle
```

产物位于 `desktop/src-tauri/target/release/bundle/nsis/`。安装器采用当前用户模式，不请求管理员权限；Windows 10/11 缺少 WebView2 时由安装器下载 bootstrapper。

正式发布前：

1. 使用受信任的代码签名证书配置 Tauri `bundle.windows.signCommand` 或 CI 签名步骤，配置不得包含在仓库中。
2. 验证应用 EXE、NSIS 安装器和卸载器签名均有效，证书主题与发布者一致。
3. 在干净的 Windows 10/11 用户账户测试安装、托盘启动和开机启动开关。
4. 使用相同 identifier 覆盖安装旧版本，确认数据库 migration、可信设备和设置保留。
5. 卸载后确认程序、快捷方式和开机启动项被移除。用户数据默认保留，避免误删历史和凭据；完全清理应由用户主动执行。

回滚时重新安装上一个已签名版本。仅当其数据库 schema 兼容当前数据时允许直接降级；否则先备份应用数据并恢复对应版本备份，不能手工编辑数据库或凭据库。

## HarmonyOS HAP

共享配置生成未签名内部检查包：

```powershell
.\scripts\build-harmony-release.ps1
```

EggClip 仅声明 `INTERNET` 和 `GET_NETWORK_INFO`。PasteButton 在用户点击时提供一次性剪贴板授权，不申请后台或静默剪贴板读取能力。应用备份被禁用，因为 RDB 中的 HUKS 引用不能脱离设备安全存储独立恢复。

正式发布前：

1. 在 DevEco Studio 本机配置或 CI secret 中注入正式签名，禁止提交证书、密码和本机路径。
2. 递增 `versionCode` 和 `buildVersion`，确认 `versionName` 与桌面端一致。
3. 用正式签名 HAP 覆盖安装上一版本，验证 RDB migration、HUKS 密钥引用、可信设备和历史均可读取。
4. 在手机和平板真机验证权限说明、PasteButton、网络切换、前后台、锁屏和自动重连。
5. 执行发布包秘密检查，并在 AppGallery Connect 中复核隐私说明与实际权限一致。

HarmonyOS 回滚优先发布修复版本，不直接降低 `versionCode`。若必须回退代码，应提高 `versionCode` 并使用上一个稳定代码构建新包；不得从另一设备恢复 RDB/HUKS 组合数据。
