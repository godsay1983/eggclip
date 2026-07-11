# EggClip 桌面端开发 TODO

本清单只记录可验收功能、真机验收和明确待办。实现细节、测试过程与排障记录写入 handoff 或提交说明；后续开发只勾选既有项目，不新增子项。

## 当前阶段

- Windows 桌面端已具备本地剪贴板监听、历史、设置、托盘、配对邀请和认证会话基础。
- 与 HarmonyOS 的邀请配对、初始空间密钥交付和同一会话内正式 `ITEM_LIVE` 收发已接线。
- 当前主线：可靠连接、重连补同步与双端真机互通。

## D0：工程基线

- [x] Tauri 2、Svelte 5、Rust、SQLite 工程与基础目录。
- [x] 应用图标、主题、主面板、设置弹层和托盘基础行为。
- [x] Windows 凭据库与 SQLite migration 基础。

## D1：Windows 剪贴板与网络 POC

- [x] Win32 文本剪贴板监听、写入、256 KiB 限制和回环抑制。
- [x] WebSocket 手动连接、mDNS POC 发布、网络诊断和 POC 收发。
- [x] Windows 真机剪贴板与局域网 POC 回归。

## D2：本地数据与同步核心

- [x] 不可变 `ClipboardItem`、HLC、来源序号、RDB 历史和 retention。
- [x] 本地复制先持久化、再异步处理；网络失败不阻塞本机复制。
- [x] 区分 `ITEM_LIVE` 与 `ITEM_BATCH`，并执行实时写入/历史不覆盖策略。
- [x] 本地复制在唯一认证同步空间中加密持久化并发送正式 `ITEM_LIVE`。
- [x] 历史正文解密预览、复制与详情展开。

## D3：版本化协议与端到端安全

- [x] v1 envelope、握手、AEAD、重放防护和共享测试向量。
- [x] Ed25519 身份、X25519、HKDF、AES-GCM、Windows 凭据库空间密钥。
- [x] 邀请二维码/字符串、一次性消费、AUTH_PROOF、AUTH_OK 和初始空间密钥交付。
- [x] 认证会话中正式 `ITEM_LIVE` 入站与出站。
- [x] 完整认证会话生命周期、错误关闭和多空间目标选择。
- [x] 与 HarmonyOS 的 HUKS HMAC 真机互通验收。

## D4：自动发现、可靠连接与补同步

- [x] 正式 mDNS 发布/浏览、最近可信地址回退和手动诊断入口。
- [x] ConnectionManager：单连接去重、心跳、前后台/网络切换处理、指数退避重连和状态事件。
- [x] `SYNC_HEADS`、范围请求、`ITEM_BATCH`、ACK、retention gap 与断线续传。

## D5：桌面产品体验

- [x] 剪贴板主面板、历史摘要、同步状态、主题和基础设置。
- [x] 邀请、诊断、同步空间和 POC 边界提示。
- [ ] 可信设备管理：真实设备状态、重命名、移除和空间密钥轮换。
- [ ] 托盘在线设备数、暂停/恢复、设备管理和状态 tooltip。

## D6：自动化与 Windows 回归

- [ ] 覆盖 clipboard、storage、protocol、crypto、sync、ConnectionManager 和 Svelte store 的完整自动化测试。
- [ ] Windows 10/11、DPI、多显示器、防火墙、Wi-Fi/睡眠切换、快速连续复制的手动回归。
- [ ] 记录双端 2 小时稳定运行和无回环风暴回归。

## D7：发布准备

- [ ] NSIS 安装包、元数据、代码签名、升级/卸载与回滚清单。
- [ ] 隐私说明、局域网排障、发布包秘密与调试产物检查。

## 暂不计划

- macOS/Linux 正式支持。
- 图片、文件、HTML、富文本、账号、云服务、公网中继、遥测和自动更新。
- 多同步空间和团队权限。
