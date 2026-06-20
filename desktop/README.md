# EggClip Desktop

EggClip 桌面端是基于 Tauri 2、Svelte 5 和 Rust 的 Windows 托盘应用。当前阶段只完成工程基线和产品空壳；剪贴板监听、局域网连接和安全配对按根目录开发计划逐阶段实现。

## 开发

```powershell
pnpm install
pnpm tauri dev
```

应用启动后默认隐藏，请从系统托盘打开“蛋定 Clip”。

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

完整计划见根目录 `DESKTOP_DEVELOPMENT_TODO.md`，架构决策见 `docs/EggClip最佳实现方案.md`。

