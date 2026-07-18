# EggClip AppGallery 素材

中英文应用名称、短介绍、详细介绍、截图文案和更新说明见 [`APP_STORE_COPY_ZH_EN.md`](./APP_STORE_COPY_ZH_EN.md)。提交前应按目标商店的当前字符限制粘贴并复核，不能把中文和英文内容混填到同一个语言条目。

## 市场图标

- 上传文件：`app-icon-opaque.png`
- 本地预览：`app-icon-opaque-preview.png`，仅用于检查浅色和深色背景，不要上传。
- 格式：216 × 216 PNG。
- 背景：纯色 `#FFF8E7`。
- 图案来源：HarmonyOS 运行时分层图标的前景层。
- 安全边距：四周至少 16 px。
- 透明度：市场图标不包含透明像素。

市场图标是单独的扁平化素材。不要用它替换 `harmony/AppScope/resources/base/media/` 或
`harmony/entry/src/main/resources/base/media/` 中的运行时分层图标。

上传前在仓库根目录运行：

```powershell
.\scripts\check-harmony-market-icon.ps1
```

上传到 AppGallery Connect 后，应分别检查浅色和深色市场预览，确认图案没有被裁切且背景边界正常。
