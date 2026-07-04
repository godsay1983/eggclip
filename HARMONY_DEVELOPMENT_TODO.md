# EggClip HarmonyOS 开发 TODO

本文档规划 HarmonyOS 6 客户端从 DevEco 空工程到可发布 MVP 的开发顺序。HarmonyOS 端是前台同步客户端，不复制桌面端后台常驻行为。

## 当前工程分析

- 工程根目录：`D:\Develop\eggclip\harmony`
- 应用包名：`com.eggclip.app`
- target SDK：`6.1.1(24)`
- compatible SDK：`6.1.0(23)`
- 设备类型：phone、tablet
- 模型：Stage Model
- 入口 Ability：`EntryAbility`
- 当前首页：`entry/src/main/ets/pages/Index.ets`
- 当前状态：H0 工程基线、主题、目标模块目录和空壳首页已建立；HarmonyOS 图标已与桌面端同源，H1 已声明网络 POC 所需最小权限，首页已接入真实 PasteButton、pasteboard 纯文本读取、严格 IPv4 手动连接、Desktop ↔ Harmony 临时文本收发、用户触发复制到本机、前台 mDNS 搜索、动态连接状态和前后台连接清理；发送与接收统一执行 256 KiB 正文和 1 MiB 外层帧边界，首页显示接收/接受/拒绝计数及上次拒绝类型，不记录正文。H1 真机手动回归已通过并记录到 `docs/MANUAL_REGRESSION.md`。共享协议开发已开始，ArkTS 已实现 v1 envelope、message type、ciphertext、hello 和 clipboard item 解析校验。
- 参考项目：`D:\Develop\EggDoneHarmony\EggDone`
- 架构基线：`docs/EggClip最佳实现方案.md`

当前 `build-profile.json5` 已改为无签名材料的共享配置。历史提交 `74d9bb1` 曾包含本机签名配置，相关证书/密码仍需轮换，并决定是否重写远端 Git 历史。

## 目标目录

```text
harmony/entry/src/main/ets/
├─ entryability/
├─ pages/
│  ├─ HomePage.ets
│  ├─ PairingPage.ets
│  ├─ DevicesPage.ets
│  └─ SettingsPage.ets
├─ components/
│  ├─ clipboard/
│  ├─ devices/
│  ├─ pairing/
│  ├─ settings/
│  └─ common/
├─ models/
├─ store/
├─ data/
│  ├─ db/
│  ├─ migrations/
│  └─ repositories/
├─ services/
│  ├─ discovery/
│  ├─ transport/
│  ├─ clipboard/
│  ├─ crypto/
│  ├─ pairing/
│  └─ sync/
├─ theme/
└─ utils/
```

## H0：工程与安全基线

### 已完成的空工程工作

- [x] 使用 DevEco Studio 创建 ArkTS Stage Model 工程。
- [x] 设置 Bundle Name 为 `com.eggclip.app`。
- [x] 设置 target SDK `6.1.1(24)`。
- [x] 设置 compatible SDK `6.1.0(23)`。
- [x] 启用 phone 和 tablet 设备类型。
- [x] 生成 EntryAbility、资源和基础测试目录。

### 首次提交前阻断项

- [x] 制定 `build-profile.json5` 本机签名处理方案，不提交 `material` 内容。
- [x] 确认当前工作树的 `.p12`、`.p7b`、`.cer`、本机路径和密码字段均不进入版本库。
- [x] 扩充 `.gitignore`：`.hvigor/`、`.idea/`、`oh_modules/`、`local.properties`、build、测试输出和本地数据库。
- [x] 检查 Git 暂存内容，确认没有签名、缓存和依赖目录。
- [x] 将 vendor 从模板值改为项目正式值。
- [x] 将版本策略调整为开发期 `0.1.0`，并记录 versionCode 递增规则。

### 工程基础

- [x] 替换模板 App/Ability 名称和字符串资源为 EggClip / 蛋定 Clip。
- [x] 使用 `docs/icon.png` 生成或适配 HarmonyOS 分层图标和启动图。
- [x] 建立 `Colors.ets`、`Spacing.ets` 和 `Typography.ets`。
- [x] 建立亮色、暗色和跟随系统资源。
- [x] 建立上述目标模块目录和空入口。
- [x] 将 `Index.ets` 改为轻量路由入口，不在其中堆积业务。
- [ ] 统一 ArkTS linter、格式和测试命令。
- [x] 编写 HarmonyOS 本地 README 或在根 README 中补充运行方式。

验收标准：

- 模拟器和至少一台真机能启动 EggClip 空壳首页。
- 手机和平板预览不报错。
- `hvigorw test` 和 `assembleHap` 通过。
- `git status` 不包含缓存、依赖、签名材料和本机配置。

## H1：前台网络与剪贴板 POC

本阶段先验证 HarmonyOS 平台能力，不做正式配对和完整 UI。

### mDNS

- [x] 在 `module.json5` 声明 POC 所需最小网络权限。
- [x] 使用 `@ohos.net.mdns` 搜索 `_eggclip._tcp.local.`。
- [x] 展示发现服务的地址、端口和协议版本，不记录敏感 TXT 字段。
- [x] 实现开始搜索、停止搜索、重复回调去重和页面销毁清理。
- [x] 验证真机 Wi-Fi、访客网络和 AP 隔离下的行为。

### WebSocket

- [x] 使用 NetworkKit WebSocket 连接桌面 POC server。
- [x] 实现 open、message、error、close 监听。
- [x] 实现连接超时、主动关闭、页面销毁和应用进入后台时的清理；前后台恢复已完成真机验证。
- [x] 增加最大消息大小和基础 JSON 校验。
- [x] 先支持手动 IP，mDNS 发现结果作为候选地址。

### 剪贴板

- [x] 使用真实 ArkUI `PasteButton` 构建“粘贴并发送”操作。
- [x] 点击授权成功后调用 Pasteboard 读取纯文本。
- [x] 授权失败、空剪贴板、不支持格式和超过 256 KiB 时显示明确错误。
- [x] 连接桌面 POC 后，PasteButton 读取成功可发送临时 `clipboardText` JSON。
- [x] 收到桌面 POC 文本后只显示预览，不自动写入系统剪贴板。
- [x] 用户点击“复制到本机”后调用 `pasteboard.setData()`。
- [x] 不申请或依赖普通三方应用无法获得的 `READ_PASTEBOARD` 常规权限路径。

验收标准：

- HarmonyOS 真机能发现或手动连接 Windows POC 服务。
- 用户点击 PasteButton 后可将本机文本发送到桌面端。
- HarmonyOS 收到桌面文本后可由用户点击复制。
- App 切到后台后停止 POC 连接，回到前台可以恢复。
- 模拟器结果只作辅助，不能代替本阶段真机验收。

## H2：本地模型、RDB 和页面结构

### 模型和 store

- [x] 定义 `ClipboardItem`、`Device`、`Space`、`SyncHead`、`ConnectionState` 和 `AppSettings`。
- [ ] 定义 `ClipboardStore`、`ConnectionStore`、`DeviceStore` 和 `SettingsStore`。
  - [x] 新增 `SettingsStore`，集中处理设置加载、保存、默认值、校验和错误状态。
- [ ] store 统一处理 loading、empty、ready、offline 和 error 状态。
- [ ] 页面不直接操作 RDB 和网络 service。

### ArkData RDB

- [x] 创建 `schema_migrations`。
- [x] 创建 `clipboard_items`、`devices`、`spaces`、`sync_heads` 和 `app_metadata`。
- [x] 实现 transaction 和顺序 migration runner。
- [x] 实现 ClipboardRepository、DeviceRepository、SpaceRepository 和 SettingsRepository。
  - [x] 建立 repository SQL command 层，覆盖 Clipboard、Device、Space、SyncHead 和 Settings。
  - [x] 接入真实 RDB repository 服务层，复用 command 层执行 Space、Device、Clipboard、SyncHead 和 Settings 读写。
- [x] 生成并持久化随机 `deviceId` 和本机 `originSeq`。
  - [x] 建立本机 `deviceId` 与 `nextOriginSeq` 的 repository SQL command 层；随机生成与真实 `relationalStore` 持久化待接入。
  - [x] 建立本地剪贴板持久化命令计划：由 PasteButton 明文生成 `ClipboardItem`、写入 `encrypted_content`、推进 `originSeq`；真实 transaction 执行和广播接入待后续服务编排实现。
  - [x] 接入 `LocalIdentityRdbRepository`，使用真实 RDB 保存本机 `deviceId`，并以 transaction 分配/推进 `originSeq`。
  - [x] 接入 `LocalClipboardPersistenceService`，将 PasteButton 明文、digest 和 encrypted blob 编排为真实 RDB transaction；事务成功后返回广播调度/跳过状态，真实 WebSocket 发送待后续接入。
  - [x] 首页 PasteButton 读取成功后已调用本机历史持久化服务，并刷新最近历史数量和元数据列表；当前 digest 为本地过渡值，正式 HMAC 待 CryptoFramework/HUKS 接入。
- [x] 实现最近 50 条、最长 7 天 retention。
  - [x] 建立 retention SQL command 层并通过真实 RDB transaction runner 执行，覆盖过期清理、数量超限和清空历史。
- [x] 支持历史数量 0、20、50、100。
  - [x] command 层已按 `AppSettings` 校验 0、20、50、100，非法历史数量拒绝生成清理命令。
- [ ] 为新库、重复 migration 和旧版本升级添加测试。

### 页面和主题

- [ ] HomePage：连接状态、最新收到、PasteButton、最近历史。
  - [x] 将首页从 POC/debug 信息堆叠改为产品化首屏：标题卖点、连接主卡、自动发现、手动连接、剪贴板收发和最近记录卡片；保留 PasteButton 和诊断信息但降低视觉优先级。
  - [x] 将首页可见内容收敛到剪贴板相关功能：最新收到、PasteButton 和最近历史；连接发现入口移出首页展示。
  - [x] 在首页品牌区展示与桌面端同源的 EggClip 应用图标。
  - [x] 将 mDNS 发现、候选连接和手动 WebSocket 连接逻辑从首页迁出，通过共享连接 store 供首页剪贴板收发复用。
  - [x] 接入 `HistoryStore` 读取本机历史数量摘要，首页最近历史卡片展示有效历史数量，不读取或展示剪贴板正文。
  - [x] 首页最近历史卡片展示最近 5 条历史元数据：大小、来源设备短标识和接收时间；正文预览待密钥解密链路接入。
  - [x] 首页最近历史卡片支持单条删除和清空本机历史；只做本机 RDB 逻辑删除，不修改系统剪贴板。
- [ ] PairingPage：扫码/邀请导入和人工确认。
  - [x] PairingPage 已接入设备页，可输入 `eggclip://pair` 邀请并展示解析结果、过期剩余、发行设备短指纹和六位确认码。
  - [x] 已接入“确认码一致，继续配对”的内存 pending 状态骨架；当前不创建 trusted device、不保存邀请 secret、不接收 spaceKey。
  - [ ] 扫码、真实握手和真实配对状态持久化待接入。
- [ ] DevicesPage：设备状态、重命名、移除。
  - [x] 将设备页占位文案改为正式空状态和设备规则卡片，明确配对、可信设备和移除轮换边界；真实设备列表、重命名和移除待配对流程接入。
  - [x] 设备页承接 POC 阶段连接入口：连接状态、mDNS 自动发现、候选地址连接、手动 IP/WebSocket 连接和断开操作。
  - [x] 设备页增加连接排障卡：根据发现/连接状态提示 mDNS、手动 IP、防火墙、AP 隔离和 VPN/TUN 检查项。
  - [x] 设备页增加运行时设备卡，将 POC 连接标记为“实验连接”，展示短指纹占位、最后在线、端点和未配对说明。
  - [x] 设备页已收敛信息架构：主页面只展示配对、可信设备和规则，运行时设备、自动发现、手动连接和排障移入“连接诊断”折叠区。
- [ ] SettingsPage：历史、隐私、主题和诊断。
  - [x] 接入可见设置页和底部导航入口，支持读取/保存自动同步、自动接收、自动写入、历史数量和保留天数；主题和诊断待补。
  - [x] 接入亮色、暗色和跟随系统主题设置，并在应用入口加载时应用主题偏好。
- [ ] 手机使用单栏；平板使用设备/历史与内容预览双栏。
  - [x] 将底部入口从铺满原生 Tabs 调整为官方 HDS Tabs 悬浮式底部页签：首页、设备、设置，并为页面内容预留底部安全空间。
  - [x] 将底部页签按钮改为同风格几何图形图标，避免图形和文字/系统图标混用。
- [ ] 复用 EggDoneHarmony 的视觉 token 思路，不复制 Todo 组件和业务状态。

验收标准：

- 应用重启后本机 ID、历史和设置保持。
- RDB 错误不会造成页面白屏。
- 360vp 手机和常见平板宽度下内容不截断、不拥挤。
- 首页使用真实 PasteButton，不能被普通自定义按钮替换。

## H3：设备身份与本地密钥

### HUKS/CryptoFramework

- [ ] 验证目标 SDK 上 Ed25519、X25519、HKDF 和 AES-GCM 的具体 API。
- [ ] 生成 Ed25519 长期设备身份。
- [ ] 将私钥和 `spaceKey` 保存到 HUKS 或等效系统安全存储。
  - [x] 建立 `spaceKey` HUKS alias/引用生成与校验边界；RDB repository 只接收 `huks://` 引用，不保存裸 key。
  - [ ] 真实 HUKS import/generate 和读取流程待真机验证后接入。
- [ ] RDB 只保存公钥、密钥版本和安全存储 alias。
- [ ] 实现密钥存在、缺失、损坏和重新初始化路径。
- [ ] 禁止日志输出密钥、邀请、正文、HMAC 摘要和完整帧。

### 跨语言测试向量

- [ ] 读取 `protocol/test-vectors/`。
  - [x] ArkTS 已镜像消费协议 JSON fixture。
  - [x] ArkTS 已镜像校验 crypto 向量形状、字节长度、transcript 和 nonce 规则。
  - [x] 新增共享 crypto fixture 生成脚本，从 `protocol/test-vectors/crypto/` 生成 ArkTS 单测 fixture 模块。
  - [ ] ArkTS 测试直接从 `protocol/test-vectors/` 读取 crypto 文件。
- [ ] ArkTS 实现通过 Ed25519 签名/验签向量。
  - [x] 本地 SDK 类型已确认存在 CryptoFramework/HUKS Ed25519 相关入口。
  - [x] AUTH_PROOF canonical transcript 构造已与 Rust/fixture 对齐。
  - [x] 建立 Ed25519 CryptoFramework 验签导入边界，覆盖 SPKI DER 和 ED25519 KeySpec 尝试路径；本地单元环境尚未验过 RFC 8032 向量。
  - [ ] 接入 CryptoFramework/HUKS Ed25519 真验签。
  - [ ] 在 HarmonyOS 6.1 真机上确认 Ed25519 算法名、公钥导入格式和空消息 one-shot 验签行为。
- [ ] ArkTS 实现通过 X25519/HKDF 派生向量。
  - [x] 本地 SDK 类型已确认存在 X25519 与 HKDF 相关入口。
  - [x] session key 与 nonce 向量规则已固定。
  - [ ] 接入 CryptoFramework/HUKS X25519/HKDF 真派生。
- [ ] ArkTS 实现通过 AES-GCM 加解密和篡改拒绝向量。
  - [x] 本地 SDK 类型已确认存在 AES-GCM 参数入口。
  - [x] AES-GCM frame 字段、nonce 和 AAD 规则已有 ArkTS 校验基础。
  - [x] canonical encrypted AAD 构造已与 Rust 规则对齐。
  - [ ] 接入 CryptoFramework/HUKS AES-GCM 真加解密。
- [x] 明确字节序、字符串编码、Base64 变体和 transcript 规范化规则。

验收标准：

- Rust 与 ArkTS 对相同输入生成完全一致的派生结果和密文结果。
- 私钥不会出现在 RDB、导出文件和普通日志。
- 篡改 tag、错误 nonce 和错误关联数据全部解密失败。

## H4：邀请与配对

### 邀请导入

- [x] 定义 `eggclip://pair` 邀请格式或等效版本化字符串。
  - [x] HarmonyOS 已实现 `eggclip://pair?p=` 邀请 URI 解析，校验 app、版本、kind、spaceId、spaceKeyVersion、发行设备、公钥、256-bit pairingSecret 和过期时间。
  - [x] HarmonyOS 已兼容桌面端新增 `invitationId` 字段，解析结果保留该 ID 供后续正式握手消费回传。
- [x] 已接入系统 Scan Kit 扫码入口，限制 QR_CODE，扫码结果复用现有内存导入校验路径。
- [x] 支持从剪贴文本/输入框导入邀请，但不得把邀请保存到历史。
  - [x] 已支持输入框导入邀请并只做内存解析，不写入 RDB 或本机历史。
  - [x] PairingPage 已接入真实 PasteButton 导入入口，用户授权后读取纯文本邀请并立即校验，不保存到历史或 RDB。
  - [x] PairingPage 已接入扫码导入入口，扫码文本不写入 RDB 或本机历史，直接进入邀请解析与确认码流程。
- [x] 校验 app、协议版本、spaceId、过期时间和字段长度；已覆盖 URI 总长度、payload 大小、UUID、设备名长度/控制字符、公钥和 pairingSecret 字节长度。
- [x] 邀请页面显示邀请设备名称和公钥短指纹；对旧邀请缺失设备名时回退为“桌面端 #短指纹”。

### 安全配对

- [ ] 使用 128/256 位一次性 `pairingSecret` 建立配对通道。
  - [x] PairingStore 已保留确认后的内存待握手材料，并可生成不暴露 `pairingSecret` 的 CLIENT_HELLO draft。
  - [ ] pairingSecret 参与正式配对通道派生/证明待接入。
- [ ] 完成设备身份交换和握手 transcript 验证。
  - [x] 已新增 PairingHandshakeDraftService，基于邀请、本机身份公钥和临时公钥生成 CLIENT_HELLO payload 与版本化 `pairing-invitation:v1:<invitationId>` 上下文。
  - [x] 已新增 ProtocolFrameBuilderService，将 CLIENT_HELLO draft 构造成正式明文握手 envelope，并通过 parser 与 handshake transport 门控测试。
  - [x] 已实现 SERVER_HELLO 与邀请桌面身份/同步空间的本地匹配校验，并生成 client AUTH_PROOF 所需 canonical transcript 输入。
  - [x] 已实现 client AUTH_PROOF envelope 构建：基于 canonical transcript 生成 transcriptHash，校验 64 字节 Ed25519 签名输入，并通过 parser/handshake transport 回读。
  - [ ] 真实 X25519 临时密钥生成、AUTH_PROOF 签名/验签和握手网络交换待接入。
- [x] 显示六位人工确认码供双方核对，但不把它当成唯一秘密。
  - [x] PairingPage 已显示六位人工确认码，并要求用户点击“确认码一致，继续配对”后才进入 pending；确认码不作为唯一秘密。
  - [x] PairingStore 确认后会从 UI snapshot 中清空完整邀请文本，只保留摘要和内存待握手材料。
- [ ] 安全接收 `spaceKey` 和成员信息。
- [ ] 成功后持久化 trusted device 并清理邀请秘密。
- [ ] 拒绝过期、重复消费、身份不匹配和空间不匹配邀请。

验收标准：

- 手机扫码后可以与 Windows 完成一次配对。
- 同一邀请第二次使用失败。
- 过期邀请和被篡改二维码不会创建信任记录。
- 配对失败不会遗留半完成 device 或密钥。

## H5：认证连接与同步协议

### 会话状态机

- [ ] 实现 disconnected、discovering、connecting、handshaking、authenticated、syncing、ready、failed。
  - [x] ArkTS 协议 session gate 覆盖 connecting、handshaking、authenticated、syncing、ready、failed。
  - [ ] discovering 与前台连接管理接入。
- [ ] X25519 建立临时共享秘密。
- [ ] Ed25519 验证设备身份和空间绑定。
  - [x] 固定 canonical AUTH_PROOF transcript 并在 ArkTS 校验构造结果。
  - [ ] 真实 Ed25519 验签待接 CryptoFramework/HUKS。
- [ ] HKDF 派生双向会话密钥。
  - [x] 固定共享 session key 向量并在 ArkTS 校验字段、长度和 nonce 规则。
  - [ ] 真实 CryptoFramework HKDF 未接入。
- [ ] AES-256-GCM 解密认证后业务帧。
- [ ] 维护接收计数器和 replay window。
  - [x] ArkTS 协议入站 replay guard 拒绝重复 messageId 与非递增 sessionCounter。
  - [x] ArkTS `ProtocolTransportSession` 已在已认证 transport 帧入口接入 replay guard。
  - [x] WebSocket service 已新增正式协议连接入口和 `decodeProtocolFrameMessage`，收包路径接入 `ProtocolTransportSession`。
  - [x] ArkTS `ProtocolTransportSession` 在协议拒绝、replay、超限和明文帧时进入 failed/closed，阻止后续收包。
  - [x] ArkTS `ProtocolTransportSession` 收到正式加密 `ERROR` envelope 后进入 failed/closed，不分发为业务 envelope。
  - [x] ArkTS `ProtocolHandshakeTransportSession` 已接入明文握手 envelope、状态门控、replay guard，并在 `AUTH_ERROR` / `ERROR` 时进入 failed/closed。
  - [ ] 正式连接生命周期接入已配对设备和握手派生出的真实 session。
- [ ] 未认证连接不能访问同步 service 和 RDB 正文。
  - [x] ArkTS 协议 session gate 已拒绝认证前业务帧。
  - [x] ArkTS `ProtocolTransportSession` 已拒绝 POC 明文 JSON 进入正式协议入口。
  - [x] WebSocket service 正式协议入口已与 POC 明文入口分离。
  - [ ] sync service 和 RDB 接入认证状态。

### 前台连接

- [ ] App 前台时自动发现已配对桌面端。
- [ ] 优先连接最近成功桌面端，失败后尝试其他 trusted desktop。
  - [x] POC 阶段已在设备页持久化最近成功桌面地址，支持重启后回填和快速连接，并明确该地址不代表 trusted device。
- [ ] 同一 peer 只保留一条 WebSocket。
- [ ] 实现 PING/PONG、前台重连和带 jitter 的退避。
- [ ] App 进入后台时安全停止发现和连接；回前台重新同步。

### 补同步

- [ ] 发送本地 `SYNC_HEADS`。
- [ ] 按来源设备和 `originSeq` 请求缺失范围。
- [ ] 处理 `ITEM_BATCH`、ACK 和 retention gap。
- [ ] batch 持久化成功后更新 sync head。
- [ ] 补到的记录只进入历史，不自动写入 HarmonyOS 剪贴板。
- [ ] 对 itemId、来源序号和 HMAC digest 去重。
- [ ] 使用 HLC 稳定排序，不使用设备本地时间作为唯一决胜依据。

### HarmonyOS → Desktop

- [x] PasteButton 授权读取成功后创建本地不可变 item。
  - [x] 读取成功会先写入本机 RDB 历史并刷新首页最近记录；正文仍不在 UI 展示。
- [ ] 本地持久化成功后发送 `ITEM_LIVE`。
  - [x] POC 发送路径已在 PasteButton 读取后读取本机同步策略；自动同步关闭时只更新本机历史，不发送临时文本。
  - [x] POC 发送路径已调整为先确认本机历史/本机记录事务，再检查同步策略和 WebSocket 连接，避免本机保存失败时仍显示发送成功。
- [ ] 网络失败时保留待同步记录，不能假装发送成功。
- [ ] 显示已发送、待同步和失败状态。
  - [x] 首页增加发送状态卡，区分本机记录、待连接、发送中、已发送、失败和同步暂停。

验收标准：

- 打开 App 后自动连接已配对桌面端并拉取缺失记录。
- 历史 batch 不会覆盖手机当前剪贴板。
- PasteButton 发送的 item 能实时写入在线桌面端。
- 错误密钥、重放、乱序、重复和超限帧均按协议处理。

## H6：设备、设置与移动端体验

### 首页

- [x] 最新收到卡片显示预览、来源、时间和“复制到本机”。
- [ ] PasteButton 作为主要发送入口。
- [ ] 最近历史支持复制、删除和详情展开。
  - [x] 设置页已接入清空本机历史；首页历史复制和详情展开待接入。
  - [x] 首页已展示本机历史数量摘要和最近 5 条元数据；正文预览、复制和详情展开待接入。
  - [x] 首页最近历史已接入单条删除，删除后通过 `HistoryStore` 刷新数量和列表；不修改系统剪贴板。
  - [x] 首页最近历史已接入清空本机历史，清空后刷新数量和列表；不修改系统剪贴板。
  - [x] PasteButton 读取成功后写入本机历史，首页最近历史立即刷新。
- [x] 长文本默认折叠，显示字符数和大小。
  - [x] 最新收到卡片长文本默认折叠，展示字符数，并支持展开/收起；历史正文仍不展示。
- [ ] 在线、连接中、离线、认证失败和暂停状态使用不同反馈。
  - [x] 设备页连接卡已展示状态标签，状态点已区分在线、连接中、认证失败、暂停和离线颜色；正式认证失败/暂停状态流待协议和同步策略接入。
  - [x] 自动接收关闭时，鸿蒙端收到桌面 POC 文本会进入暂停反馈并忽略预览。
- [ ] 首次使用、无设备、无历史和网络失败空状态完整。
  - [x] 首页剪贴板空状态已根据连接失败/暂停展示下一步提示；最近记录空状态已区分“无历史”和“历史保存已关闭”，并说明历史只显示元数据。
  - [x] 设备页网络失败路径已提供可操作排障说明，并明确候选地址不等于可信设备。

### 设备管理

- [ ] 显示设备名称、公钥短指纹、在线状态和最后在线时间。
  - [x] POC 阶段已展示运行时设备名称、状态、短指纹占位、最后在线语义和端点；真实公钥短指纹待安全配对接入。
- [x] POC 阶段在设备页显示连接状态、发现候选和手动连接入口；正式 trusted device 列表待配对流程接入。
- [ ] 支持设备重命名和移除。
- [ ] 移除设备时显示空间密钥轮换影响。
- [ ] 支持重新配对，不复用旧邀请秘密。

### 设置和隐私

- [ ] 历史数量和最长保留时间设置。
  - [x] SettingsPage 已通过 `SettingsStore` 读写历史数量和保留天数。
  - [x] 保存历史数量、保留天数或关闭历史时，会立即对已有本机历史执行 retention 清理。
- [ ] 清空历史和重置本机身份入口。
  - [x] SettingsPage 已接入“清空本机历史”入口，通过 `SettingsStore` 调用 RDB repository 标记删除全部本机历史，不修改系统剪贴板。
  - [ ] 重置本机身份入口待身份密钥/HUKS 流程明确后接入。
- [x] 亮色、暗色和跟随系统主题。
- [ ] 局域网诊断：mDNS、候选地址、WebSocket 状态和错误码。
  - [x] SettingsPage 已增加局域网诊断卡：展示 mDNS 状态、候选数量、WebSocket 状态和帧统计。
- [x] 隐私说明：无云服务、前台同步、用户触发读取和本地保留。
- [x] 诊断信息不显示正文、摘要、邀请和密钥。
  - [x] 局域网诊断卡只展示连接状态、候选数量和错误类型，不展示正文、摘要、邀请或密钥。

### 生命周期与适配

- [ ] 前后台切换不会重复创建 listener 和 timer。
- [ ] 页面销毁时释放 mDNS searcher 和 WebSocket。
- [ ] 网络切换时刷新候选地址和连接状态。
- [ ] 手机单栏和平板双栏共享业务 store。
- [ ] 尊重系统字体缩放、暗色模式和减少动态效果。

验收标准：

- 常用“接收并复制”和“粘贴并发送”均在两次点击内完成。
- 手机和平板没有裁切、遮挡和横向溢出。
- 连续前后台切换不会产生重复连接、重复消息或 listener 泄漏。

## H7：测试与发布准备

### 自动化测试

- [ ] RDB：migration、CRUD、retention 和 sync heads。
- [ ] Protocol：解析、版本、字段长度、batch 和错误消息。
- [ ] Crypto：共享向量、篡改、重放和计数器。
- [ ] Sync：live/batch、range、gap、重复和 HLC。
- [ ] Stores：加载、离线、错误、PasteButton 结果和前后台状态。
- [ ] UI smoke：手机首页、平板布局、配对和设置导航。

### 真机回归

- [ ] HarmonyOS 手机和平板。
- [ ] mDNS 正常、mDNS 被阻断、手动 IP 和最近地址回退。
- [ ] Wi-Fi 切换、前后台、锁屏恢复和桌面端重启。
- [ ] PasteButton 成功、临时授权失败、空文本和超限文本。
- [ ] 配对成功、过期、重复使用、错误确认码和设备移除。
- [ ] 中英文、Emoji、多行、最大文本和快速连续发送。

### 发布

- [ ] 使用正式应用名称、图标、启动页、版本和 vendor。
- [ ] 只声明实际使用且可获批的权限。
- [ ] 准备隐私说明和应用市场权限说明。
- [ ] 使用正式签名/Profile 构建 release HAP/App。
- [ ] 确认发布包不包含测试密钥、邀请、日志、RDB、缓存和本机路径。
- [ ] 编写发布前回归、升级和回滚清单。

验收标准：

- `hvigorw test`、`assembleHap` 和发布构建通过。
- 正式签名真机完成桌面双向互通。
- 应用市场权限集合不依赖 `system_basic` 的常规剪贴板读取能力。
- 发布包和仓库均不包含签名秘密与本机配置。

## 推荐里程碑

| 版本 | 范围 |
| --- | --- |
| `0.1.0-poc` | H0–H1：工程、真机 mDNS/WebSocket/PasteButton POC |
| `0.2.0-alpha` | H2–H4：本地数据、页面、HUKS 和配对 |
| `0.3.0-beta` | H5–H6：正式协议、同步和完整移动体验 |
| `1.0.0` | H7 与 Windows 正式互通、签名和发布回归 |

## 暂不计划

- 后台常驻、后台静默剪贴板读取和自动写入。
- 桌面卡片、通知和后台任务。
- 图片、文件、HTML 和富文本同步。
- 账号、服务器、S3、公网中继和远程推送。
- 多同步空间和团队权限。
- 依赖 `READ_PASTEBOARD` system_basic 权限的发布方案。
