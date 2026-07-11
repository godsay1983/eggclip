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

