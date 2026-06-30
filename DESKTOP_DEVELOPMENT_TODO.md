# EggClip 桌面端开发 TODO

本文档规划 Windows 桌面端从空目录到可发布 MVP 的开发顺序。阶段按依赖关系排列；除阻断缺陷外，不跨阶段开发。

## 当前状态

- 工程目录：`D:\Develop\eggclip\desktop`
- D0 工程基线已建立，桌面 UI 已拆出 TypeScript API / store / component 基线；D1 剪贴板 POC 已完成主要代码链路和人工回归：文本边界、Win32 剪贴板事件监听、Windows 剪贴板同步排除标记、WebSocket POC server/手动客户端、最小 mDNS POC 发布、网卡/IPv4 诊断、POC peer/安全帧诊断状态、Desktop ↔ Desktop/Harmony 临时文本消息、100 条消息编解码回归、sequence/digest/TTL 回环抑制基础、防火墙/网络差异和真机互通。未认证 POC 只允许用户触发发送和复制。
- 目标平台：Windows 10/11。
- 目标技术栈：Tauri 2、Svelte 5、SvelteKit、TypeScript、Rust、SQLite。
- 应用标识建议：`com.eggclip.desktop`。
- 初始版本建议：`0.1.0`。
- 桌面端工程和视觉参考：`D:\Develop\EggDone`。
- 架构基线：`docs/EggClip最佳实现方案.md`。

## 目标目录

```text
desktop/
├─ src/
│  ├─ lib/
│  │  ├─ api/
│  │  ├─ components/
│  │  │  ├─ clipboard/
│  │  │  ├─ devices/
│  │  │  ├─ settings/
│  │  │  └─ common/
│  │  ├─ stores/
│  │  ├─ types/
│  │  └─ utils/
│  └─ routes/
├─ src-tauri/
│  ├─ icons/
│  └─ src/
│     ├─ app/
│     ├─ tray/
│     ├─ clipboard/
│     ├─ discovery/
│     ├─ transport/
│     ├─ protocol/
│     ├─ pairing/
│     ├─ crypto/
│     ├─ sync/
│     ├─ storage/
│     └─ settings/
└─ package.json
```

## D0：工程基线

### Tauri/Svelte 工程

- [x] 在 `desktop/` 创建 Tauri 2 + Svelte 5 + SvelteKit 工程。
- [x] 设置产品名 `EggClip`、中文名“蛋定 Clip”和标识 `com.eggclip.desktop`。
- [x] 将版本统一设置为 `0.1.0`：`package.json`、`Cargo.toml`、`tauri.conf.json` 和 `Cargo.lock`。
- [x] 使用 pnpm，固定 Node、pnpm 和 Rust 最低版本。
- [x] 配置 SvelteKit static adapter、严格 TypeScript 和路径别名。
- [x] 接入 Vitest，建立 Rust unit/integration test 目录。
- [x] 添加 `check`、`test`、`build`、`release:check` 脚本。
- [x] 完善根目录和桌面端 `.gitignore`。

### 从 EggDone 提取基础设施

- [x] 复用托盘创建、左键显隐、关闭转隐藏和失焦隐藏模式。
- [x] 复用多显示器面板定位和 DPI 计算逻辑。
- [ ] 复用单实例、开机启动和系统凭据库接入模式。
- [ ] 复用 SQLite WAL、migration runner 和参数绑定模式。
- [x] 复用 TypeScript API / store / component 分层。
- [x] 复用主题 token 和发布检查结构，不复制 Todo、提醒或 S3 业务。
- [x] 使用 `docs/icon.png` 生成 Tauri 图标集并核对透明背景效果。

### 基础页面

- [x] 建立 EggClip 空壳页面：品牌、连接状态、当前剪贴板、设备和历史区域。
- [x] 建立亮色、暗色和跟随系统主题。
- [x] 使用应用图标替换主面板品牌区临时鸡蛋标识。
- [x] 首页主内容收敛为剪贴板预览和历史；连接诊断、设备和策略设置移入设置弹层。
- [x] 启动时隐藏普通窗口，只显示托盘图标。
- [x] 再次启动时唤醒已有进程，不创建第二个托盘图标。

验收标准：

- `pnpm check`、`pnpm test`、`pnpm build`、`cargo check` 和 `cargo test` 通过。
- Windows 启动后只有一个托盘图标，左键可以显隐面板。
- 面板关闭或失焦时进程继续运行，只有“退出”菜单结束进程。
- 仓库不包含 `node_modules`、`target`、本地数据库、凭据或构建产物。

## D1：技术风险 POC

本阶段只验证核心链路，允许使用临时诊断页面，不实现正式配对和完整 UI。

### Windows 剪贴板事件

- [x] 使用 Win32 `AddClipboardFormatListener`（通过 `clipboard-win` 封装）。
- [x] 在独立窗口消息循环中接收 `WM_CLIPBOARDUPDATE`。
- [x] 读取 Unicode 纯文本并转换为 UTF-8。
- [x] 拒绝空文本和超过 256 KiB 的文本。
- [x] 实现文本写入系统剪贴板。
- [ ] 使用 digest、系统 sequence 和短时 suppression token 防止远端写入回环；核心实现与单元测试已完成，等待认证 `ITEM_LIVE` 接入后做真机闭环。
- [x] 将本机剪贴板变化通过 Tauri event 推送到前端 POC 面板。
- [x] 连续复制相同文本时验证“立即重复”和“稍后再次复制”的差异；sequence/TTL 单元测试已覆盖，Windows 真机快速复制已验收。
- [x] 尊重 `ExcludeClipboardContentFromMonitorProcessing` 和 `CanUploadToCloudClipboard=0`，并禁止 EggClip 写入被 Windows 云剪贴板上传；真机格式检查保留在手动回归。

### 手动 WebSocket

- [x] 使用 `tokio` 和 `tokio-tungstenite` 启动本地 server。
- [x] 支持手动输入 IP/端口连接另一个桌面进程。
- [x] 定义临时 POC 消息，完成双向文本传输。
- [x] 接收 HarmonyOS 端发送的临时 `clipboardText` JSON 消息并显示到面板预览。
- [x] 将当前面板文本通过临时 `clipboardText` JSON 广播给已连接 POC peer。
- [x] 发送到 POC peer 失败时清理断开的临时连接引用。
- [x] 连接和剪贴板处理运行在 Rust 后端，不阻塞 Tauri UI 线程。
- [x] 增加消息大小、连接超时和基础错误处理。
- [x] 验证 Windows 防火墙首次提示和专用/公用网络差异。

验收标准：

- 两台 Windows 通过手动 IP 连续双向复制 100 次，无无限回环和重复风暴。
- 断开一台设备不会影响另一台本地复制。
- 256 KiB 边界、Emoji、中文、多行文本和空文本行为明确。
- POC 结果和平台限制记录到 `docs/`，通过后再进入正式协议开发。

## D2：本地数据与同步核心

### 数据模型

- [x] 定义 `ClipboardItem`、`Device`、`Space`、`SyncHead` 和 `AppSettings`。
- [x] 为本机生成并持久化随机 `deviceId`。
- [x] 为本机事件维护持久化单调 `originSeq`。
- [x] 实现 Hybrid Logical Clock，用于跨设备稳定排序。
- [x] 使用 UUID v7 生成 `itemId`。
- [x] 使用 HMAC-SHA-256 生成内容摘要，不保存裸 SHA-256。

### SQLite

- [x] 创建 `schema_migrations`。
- [x] 创建 `clipboard_items`、`devices`、`spaces`、`sync_heads` 和 `app_metadata`。
- [x] 开启 WAL、foreign keys 和 busy timeout。
- [x] 实现可重复、事务化 migration。
- [x] 为新库初始化和重复 migration 建立测试夹具；旧版本升级夹具待 v2 migration 出现后补齐。
- [x] 实现 `SpaceRepository`、`DeviceRepository`、`ClipboardRepository`、`SyncHeadRepository` 和 `SettingsRepository` 基础 CRUD，正文只保存为 `encrypted_content`。
- [x] 实现最近 50 条、最长 7 天的 retention 清理。
- [x] 支持历史数量 0、20、50、100。
- [x] 保存历史数量、保留天数或关闭历史时，会立即对已有本机历史执行 retention 清理。
- [x] 明确“清空历史”只保证逻辑删除和数据库清理，不承诺物理不可恢复擦除。

### Sync Engine

- [x] 将本地复制转换为不可变 `ClipboardItem`。
  - [x] 桌面端本机读取和剪贴板监听的可见文本已接入本机历史持久化；当前只展示元数据，正文预览等待密钥解密链路接入。
- [x] 本地事务成功后再异步广播，网络失败不回滚本地记录。
  - [x] 已完成本地事务持久化边界：生成 `ClipboardItem`、写入 `encrypted_content`、递增 `originSeq` 同事务提交；网络广播接入待后续实现。
  - [x] 增加事务后广播器边界和失败回归测试：广播失败只返回状态，不回滚已提交的本地记录。
- [x] 区分 `ITEM_LIVE` 和 `ITEM_BATCH`。
- [x] 只有 `ITEM_LIVE` 可以触发桌面自动写入。
- [x] `ITEM_BATCH` 只更新历史和同步游标。
- [x] 按 `itemId`、来源序号和 digest 组合去重。
- [x] 增加暂停同步、暂停自动接收和暂停自动写入策略。

验收标准：

- 应用重启后 `deviceId`、`originSeq`、历史和设置保持。
- 数据库操作失败会显示错误，但不会造成 UI 白屏或进程退出。
- 历史补齐测试不会修改系统剪贴板。
- retention 重复运行结果稳定，不误删保留范围内记录。

## D3：版本化协议与端到端安全

### 共享协议

- [x] 创建 `protocol/README.md` 和 `protocol/v1.schema.json`。
- [x] 固定 envelope、握手、错误和同步消息字段。
- [x] 定义状态机：disconnected、connecting、handshaking、authenticated、syncing、ready、failed。
- [x] 定义最大帧、最大 batch、超时和未知版本处理规则。
- [ ] 创建 Rust/ArkTS 共用 JSON 和二进制测试向量。
  - [x] 创建 schema/解析用 JSON 初始样例。
  - [x] 补充 Ed25519、X25519、HKDF-SHA-256、AES-256-GCM、session key、AUTH_PROOF 和 replay counter 共享 crypto 向量。
  - [x] Rust 消费共享向量并执行真实算法校验。
  - [x] ArkTS 镜像校验向量形状、字节长度、transcript 和 nonce 规则。
  - [ ] ArkTS 接入平台 CryptoFramework/HUKS 后消费同一批 crypto 向量做真实算法校验。
- [x] 桌面 Rust 实现 v1 envelope、message type、ciphertext、hello、clipboard item 和 sync heads 类型。
- [x] 桌面 Rust 消费 `protocol/test-vectors/`，覆盖合法握手、加密 envelope、clipboard item、未知版本和认证后明文拒绝。
- [x] HarmonyOS ArkTS 实现同等协议类型和测试向量消费。

### 设备身份与本地密钥

- [ ] 生成 Ed25519 长期身份密钥。
  - [x] Rust 完成基于测试 seed 的 Ed25519 签名/验签基元。
  - [ ] 生产随机生成长期身份密钥。
  - [ ] 身份密钥接入系统凭据库存取。
- [ ] 使用系统凭据库保存私钥和 `spaceKey`。
- [ ] SQLite 只保存公钥、密钥版本和加密引用。
- [ ] 实现密钥加载失败、凭据缺失和凭据删除处理。
- [ ] 日志过滤器拒绝输出正文、摘要、邀请和密钥。

### 邀请和配对

- [ ] 创建同步空间并生成 256 位 `spaceKey`。
- [ ] 创建 5 分钟过期、一次性使用的高熵邀请。
- [ ] 生成二维码内容和可复制邀请字符串。
- [ ] 六位确认码只用于双方人工核对，不作为唯一秘密。
- [ ] 配对完成后持久化 trusted device。
- [ ] 拒绝过期、重复消费、空间不匹配和身份不匹配邀请。

### 会话加密

- [ ] X25519 协商临时共享秘密。
  - [x] Rust 完成基于共享向量的 X25519 基元。
  - [ ] 正式握手状态机生成并交换临时公钥。
- [ ] Ed25519 签名绑定身份、空间和握手 transcript。
  - [x] 固定 canonical AUTH_PROOF transcript。
  - [x] 固定 transcript hash 和 Ed25519 验签向量。
  - [ ] 正式握手状态机验证远端 AUTH_PROOF。
- [ ] HKDF-SHA-256 派生双向独立会话密钥。
  - [x] Rust 实现方向隔离 session key 派生并通过共享向量。
  - [ ] 正式握手 transcript 输入接入 session key 派生。
- [ ] AES-256-GCM 加密认证后全部业务消息。
  - [x] Rust AES-GCM 基元通过共享向量和 tag 篡改拒绝测试。
  - [x] 协议状态机认证门控已阻止认证前业务帧。
  - [x] Rust 协议层已实现 encrypted business frame 构造、canonical AAD、方向 nonce 校验、解密和篡改拒绝测试。
  - [x] Rust transport 已新增 authenticated session frame processor，串起正式帧序列化、parse、状态门控、replay guard 和解密边界。
  - [x] Rust authenticated session frame processor 已支持 tungstenite WebSocket `Message` 入站/出站边界。
  - [ ] authenticated session frame processor 接入真实 WebSocket 连接生命周期。
- [ ] 使用方向独立的单调计数器构造 nonce。
  - [x] Rust 实现 `directionPrefix || u64be(counter)` 并通过共享向量。
  - [x] Rust 协议层解密时校验 nonce 与方向和 `sessionCounter` 一致。
  - [x] Rust authenticated transport session 已维护出站 `sessionCounter` 并递增加密业务帧。
  - [ ] 正式 WebSocket session 生命周期接管发送计数器持久/重置策略。
- [ ] 拒绝旧计数器、重复消息、AEAD 失败和认证失败帧。
  - [x] Rust 已有 AEAD 失败测试。
  - [x] 协议入站 replay guard 拒绝重复 messageId 与非递增 sessionCounter。
  - [x] replay guard 已接入 authenticated transport session frame processor。
  - [x] replay guard 已覆盖 authenticated WebSocket text message 边界。
  - [x] authenticated transport session 在协议拒绝、replay、超限和二进制帧时进入 failed/closed，阻止后续收发。
  - [x] authenticated transport session 收到已通过 AEAD 校验的加密 `ERROR` 帧后进入 failed/closed，不分发为业务 payload。
  - [ ] replay guard 接入真实 WebSocket 收包路径。
  - [x] handshake transport session 已接入明文握手 envelope、状态门控、replay guard，并在 `AUTH_ERROR` / `ERROR` 时进入 failed/closed。
  - [ ] 真实握手/认证生命周期接入后由 `AUTH_ERROR` 关闭正式 peer session。
- [ ] 会话结束后清理临时密钥材料。
  - [x] Rust authenticated transport session close/fail 时擦除方向会话密钥并重置发送计数器。
  - [ ] 正式握手/session 生命周期结束时清理临时 X25519 secret、transcript 中间态和生产会话密钥。

验收标准：

- 抓包中没有剪贴板正文、空间密钥和业务字段明文。
- 错误密钥、未知设备、过期邀请、篡改帧和重放帧全部被拒绝。
- 同一邀请无法配对第二次。
- Rust 加密实现通过共享测试向量，且没有 nonce 重用。

## D4：自动发现与可靠连接

### mDNS

- [ ] 使用 `_eggclip._tcp.local.` 发布桌面服务；D1 已实现最小 POC 发布，正式版本待协议版本、ConnectionManager 和生命周期接管。
- [ ] TXT 只发布协议版本、临时实例 ID 和能力位。
- [ ] 不广播设备名称、空间名称、`spaceKey`、正文或长期公钥。
- [ ] 浏览局域网候选节点并交给 ConnectionManager。
- [ ] mDNS 失败时尝试最近成功地址。
- [ ] 手动 IP 始终作为诊断回退入口。

### ConnectionManager

- [ ] 每个 peer 最多保留一条 active session。
- [ ] `deviceId` 较小的一方作为预期发起者，完成双连接去重。
- [ ] 实现 PING/PONG 和失活检测。
- [ ] 实现带 jitter 的指数退避重连。
- [ ] 处理 IP 变化、网络切换、睡眠唤醒和应用重启。
- [ ] 连接状态通过 Tauri event 推送给前端。

### 补同步

- [ ] 实现 `SYNC_HEADS`。
- [ ] 按 `originDeviceId + originSeq` 请求缺失范围。
- [ ] 实现 `minimumAvailable` 和 retention gap 响应。
- [ ] 批量发送限制数量和总字节数。
- [ ] ACK 只确认持久化成功的 item。
- [ ] 断线重连后从已持久化游标继续，不重复写入。

验收标准：

- 两台桌面同时发现和拨号时最终只有一条连接。
- 重启、IP 变化、睡眠唤醒和短时断网后自动恢复。
- 离线产生多条记录后只请求缺失范围。
- mDNS 不可用时手动 IP 和最近地址仍可连接。

## D5：桌面产品体验

### 主面板

- [x] 当前剪贴板卡片显示预览、来源和时间。
  - [x] 长文本默认折叠，显示字符数，并允许用户展开/收起当前可见剪贴板内容。
  - [x] 完成首轮桌面 UI polish：品牌区产品边界标签、主状态卡强化、手动连接卡去 debug 化、设备空状态、设置弹层说明和浅/深色视觉层级优化。
  - [x] 将主页可见内容收敛到剪贴板相关功能：当前剪贴板和最近历史；连接状态、手动连接和设备概览改放到设置弹层。
- [ ] 历史列表支持复制、删除单条和清空。
  - [x] 已接入“清空本机历史”命令和桌面历史卡片按钮；只标记删除本机数据库历史，不清空系统剪贴板。
  - [x] 已接入本机历史数量摘要读取，主面板展示当前有效历史数量，不读取或展示剪贴板正文。
  - [x] 已接入最近 5 条历史元数据列表，展示大小、来源设备短标识和接收时间；正文预览待密钥解密链路接入。
  - [x] 已接入单条历史删除，删除后刷新历史数量和最近记录；不修改当前系统剪贴板。
  - [x] 已将“读取当前剪贴板”和 Windows 剪贴板监听事件写入本机历史，保存后刷新数量和最近记录。
  - [ ] 历史列表正文预览、复制和详情展开待接入。
- [x] 设备 chips 显示在线、连接中、离线和认证失败。
  - [x] 设置弹层设备 chips 已展示状态标签和状态色，主状态卡也区分认证失败与普通离线。
- [x] 长文本默认折叠，显示字符数并允许展开。
- [ ] 空状态、首次使用和网络诊断文案完整。
  - [x] 最近历史空状态已区分“无历史”和“历史保存已关闭”，说明正文预览待加密/解密链路接入，并明确清空/关闭历史不修改系统剪贴板。
  - [x] 设置弹层已增加网络排障卡：给出手动端点、防火墙、AP 隔离和 VPN/TUN 检查项。
- [x] 亮色、暗色和跟随系统主题完整适配。
- [x] 尊重减少动态效果设置。

### 设备与设置

- [ ] 创建设备、加入设备、二维码和邀请字符串入口。
- [ ] 显示公钥短指纹和最后在线时间。
- [ ] 支持设备重命名、移除和空间密钥轮换。
- [ ] 支持开机启动、自动同步、自动接收、自动写入和历史策略。
  - [x] 建立 `AppSettings` 的 Tauri command、TypeScript API 和 Svelte store 基础，并通过右上角设置按钮弹出层接入自动同步、自动接收、自动写入和历史策略基础 UI。
  - [x] 自动同步关闭时，桌面端手动发送到 Harmony 的入口进入暂停态，不发送 POC 文本。
  - [x] 自动接收关闭时，桌面端会忽略远端 POC 文本，不进入当前剪贴板预览。
- [ ] 支持暂停 5 分钟、暂停至手动恢复和托盘快速切换。
- [ ] 提供诊断页：本机地址、端口、mDNS、监听状态和防火墙提示，不显示秘密。
  - [x] 设置弹层已增加局域网诊断卡：展示 WebSocket 状态、端口、mDNS 发布状态、候选 IPv4、连接数和最近错误，不展示正文、邀请、摘要或密钥。
  - [x] 设置弹层已增加隐私边界卡，说明无账号/无云/无公网中继、本机历史和安全诊断范围。
  - [x] 设置弹层已增加手动连接排障说明，明确候选地址不代表设备可信。

### 托盘

- [ ] 菜单显示在线设备数量。
- [ ] 增加暂停/恢复、设备管理、设置、关于和退出。
- [ ] 状态变化更新 tooltip，避免频繁重建托盘造成闪烁。
- [ ] 开机启动时静默进入托盘。

验收标准：

- 常用复制同步不要求打开主面板。
- 用户可以在两次点击内暂停同步或移除设备。
- 认证错误与普通离线有不同提示。
- UI 不显示密钥、完整邀请或正文日志。

## D6：自动化与真机回归

### 自动化测试

- [ ] Clipboard adapter：本地事件、远端写入、回环抑制和大小边界。
- [ ] SQLite：migration、CRUD、retention、sync heads 和崩溃恢复。
- [ ] Protocol：schema、未知版本、超限字段和错误消息。
- [ ] Crypto：握手、派生、篡改、重放、乱序和测试向量。
- [ ] Sync：live/batch 分流、范围补齐、gap、重复和 HLC。
- [ ] ConnectionManager：双连接去重、退避、心跳和状态转换。
- [ ] Svelte stores：加载、错误、设备状态、暂停和历史操作。

### Windows 手动回归

- [ ] Windows 10 和 Windows 11。
- [ ] 100%、125%、150%、200% DPI 和多显示器。
- [ ] 专用网络、公用网络、防火墙拒绝和访客 Wi-Fi。
- [ ] 睡眠/唤醒、切换 Wi-Fi、IP 变化和路由器重启。
- [ ] 安装、覆盖升级、降级拦截和卸载。
- [ ] 开机启动、单实例、托盘退出和异常崩溃恢复。
- [ ] 中英文、Emoji、多行、最大文本和快速连续复制。

验收标准：

- 两台 Windows 连续运行 2 小时，无回环风暴、重复连接和明显内存增长。
- 所有自动化检查通过。
- 手动回归结果记录在 `docs/MANUAL_REGRESSION.md`。

## D7：Windows 发布准备

- [ ] 配置 NSIS 当前用户安装包。
- [ ] 设置公司、版权、产品名、版本和卸载信息。
- [ ] 配置 Windows 代码签名。
- [ ] 编写隐私说明：传输范围、历史保留、无云服务和平台限制。
- [ ] 编写防火墙、AP 隔离和手动 IP 故障排查。
- [ ] 验证发布包不包含测试密钥、数据库、日志、邀请和调试符号。
- [ ] 建立 release checklist 和回滚步骤。
- [ ] 暂不接入自动更新，除非单独完成签名和更新威胁模型。

验收标准：

- 干净 Windows 环境可以安装、配对、同步、升级和卸载。
- 升级保留用户数据库和系统凭据。
- 发布包通过完整 `release:check` 和手动回归。

## 推荐里程碑

| 版本 | 范围 |
| --- | --- |
| `0.1.0-poc` | D0–D1：工程、托盘、事件剪贴板、手动 WebSocket |
| `0.2.0-alpha` | D2–D3：本地历史、正式协议、配对和 E2EE |
| `0.3.0-beta` | D4–D5：mDNS、可靠连接和完整桌面体验 |
| `1.0.0` | D6–D7 与 HarmonyOS 互通、回归和签名发布 |

## 暂不计划

- macOS/Linux 正式支持。
- 图片、文件、HTML 和富文本同步。
- 账号、服务器、S3、公网中继和远程推送。
- 多同步空间和团队权限。
- 自动识别密码或 Token。
- 遥测、崩溃内容上报和未经设计的自动更新。
