# EggClip 开发约定

本文件定义 EggClip 仓库中桌面端、HarmonyOS 端和共享协议的协作规则。开始开发前先阅读本文件、对应平台 TODO 和 `docs/EggClip最佳实现方案.md`。

## 项目定位

EggClip（蛋定 Clip）是纯局域网剪贴板同步工具，不是云剪贴板平台。

v1 固定边界：

- Windows 桌面端开机启动、托盘常驻、自动发现、自动连接和自动同步。
- HarmonyOS 端只在前台发现和连接；接收后由用户点击复制，发送时使用系统 `PasteButton`。
- 只同步 `text/plain`，单条明文最大 256 KiB。
- 不依赖账号、中心服务器、S3 或公网中继。
- 默认保存最近 50 条且最长 7 天，用户可以关闭历史。
- 建议每个同步空间最多 5 台设备。

任何突破上述边界的工作都应先更新实现方案和 TODO，不能顺手加入。

## 事实来源

发生冲突时按以下顺序处理：

1. 当前用户明确要求。
2. `docs/EggClip最佳实现方案.md` 中的产品和架构决策。
3. 本文件中的工程约定。
4. `DESKTOP_DEVELOPMENT_TODO.md` 或 `HARMONY_DEVELOPMENT_TODO.md` 的阶段计划。
5. 当前代码和测试体现的既有行为。

EggDone 和 EggDoneHarmony 只作为工程与视觉参考，不能覆盖 EggClip 已确认的协议、安全和平台边界。

## 当前仓库结构

```text
D:\Develop\eggclip\
├─ AGENTS.md
├─ DESKTOP_DEVELOPMENT_TODO.md
├─ HARMONY_DEVELOPMENT_TODO.md
├─ desktop\                         # 待生成的 Tauri 2 桌面工程
├─ harmony\                         # 已生成的 DevEco Studio 工程
│  ├─ AppScope\
│  ├─ entry\
│  ├─ build-profile.json5
│  └─ oh-package.json5
├─ protocol\                        # 后续创建：协议 schema 和跨语言测试向量
└─ docs\
   ├─ EggClip最佳实现方案.md
   └─ icon.png
```

不要再为 HarmonyOS 工程增加 `harmony/EggClip/` 嵌套目录。现有 `harmony/` 就是 DevEco 工程根目录。

## 核心行为约束

以下行为属于产品不变量：

1. 桌面端收到在线实时事件时可以自动写入系统剪贴板。
2. 离线补齐的历史只能进入历史列表，不能覆盖当前系统剪贴板。
3. HarmonyOS 端不能静默读取系统剪贴板；必须由真实 `PasteButton` 触发一次性授权。
4. mDNS 只负责地址发现，不能用作身份认证。
5. 未配对设备、过期邀请、重放消息和认证失败消息必须被拒绝。
6. 收到远端内容后写入本机剪贴板，不得再次形成同步回环。
7. 本地剪贴板操作不能等待网络完成；网络失败不能阻塞本地复制。
8. 剪贴板正文、邀请秘密、密钥和摘要不得出现在普通日志中。

## 共享协议边界

共享协议文件放在 `protocol/`，Rust 和 ArkTS 各自实现，不共享运行时代码。

`protocol/` 应包含：

```text
protocol/
├─ README.md
├─ v1.schema.json
└─ test-vectors/
   ├─ handshake/
   ├─ crypto/
   ├─ sync/
   └─ errors/
```

协议规则：

- envelope 必须携带协议版本、消息类型、消息 ID 和会话计数器。
- 认证前只接受握手消息。
- 业务消息在认证后使用应用层 AEAD 加密。
- `ClipboardItem` 是不可变事件，不做 Todo 式字段合并。
- 使用 `originDeviceId + originSeq` 表示来源顺序，使用 HLC 做跨设备稳定排序。
- 使用 HMAC 内容摘要，不在网络或数据库中保存裸 SHA-256 摘要。
- `ITEM_LIVE` 与 `ITEM_BATCH` 的处理路径必须分离。
- 未知高版本协议应明确拒绝，不能静默猜测字段含义。
- 修改协议时必须同时更新 schema、Rust/ArkTS 类型、测试向量和兼容说明。

## 桌面端架构边界

目标目录：

```text
desktop/
├─ src/
│  ├─ lib/api/
│  ├─ lib/components/
│  ├─ lib/stores/
│  ├─ lib/types/
│  └─ routes/
└─ src-tauri/src/
   ├─ app/
   ├─ tray/
   ├─ clipboard/
   ├─ discovery/
   ├─ transport/
   ├─ protocol/
   ├─ pairing/
   ├─ crypto/
   ├─ sync/
   ├─ storage/
   └─ settings/
```

边界规则：

- Svelte 组件不直接访问 SQLite、系统剪贴板和网络 socket。
- `src/lib/api/` 只负责 Tauri command 和 event 的类型化封装。
- `src/lib/stores/` 负责编排 UI 状态和用户操作。
- Rust `commands` 只做参数校验和调用领域服务，不承载完整业务实现。
- `clipboard/` 通过 trait 隔离平台差异；Windows v1 使用 `AddClipboardFormatListener`。
- `transport/` 不决定剪贴板是否自动写入，该策略属于 `sync/`。
- `storage/` 负责连接、migration、repository 和 retention，不处理 UI 文案。
- `lib.rs` 只装配模块、插件和生命周期，不能重新堆积业务逻辑。

Windows 是 v1 唯一承诺平台。macOS/Linux 代码只有在存在可验证实现时才加入；条件编译不能掩盖未验证功能。

## HarmonyOS 架构边界

目标目录：

```text
harmony/entry/src/main/ets/
├─ entryability/
├─ pages/
├─ components/
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

边界规则：

- `pages/` 只组合页面、导航和页面级状态。
- `components/` 不直接访问 RDB、mDNS、WebSocket、HUKS 或 Pasteboard。
- `store/` 管理可观察状态和用户操作编排。
- `data/` 负责 RDB 初始化、migration 和 repository。
- `services/clipboard/` 封装 `PasteButton` 授权后的读取和用户点击后的写入。
- `services/transport/` 只负责连接和帧收发；同步策略放在 `services/sync/`。
- `EntryAbility.ets` 只处理应用生命周期和依赖装配。
- 尽快把模板 `Index.ets` 改为轻量入口，禁止把业务集中到一个页面文件。

HarmonyOS v1 目标为 SDK `6.1.1(24)`，compatible SDK 为 `6.1.0(23)`，设备类型为 phone 和 tablet。改变 SDK 下限前必须核对 mDNS、WebSocket、PasteButton、CryptoFramework 和 HUKS 的可用版本。

## 安全约定

- 使用 Ed25519 设备身份、X25519 临时密钥交换、HKDF-SHA-256 和 AES-256-GCM。
- 不自行更换或简化密码算法，不使用固定 nonce、可预测随机数或六位数字作为唯一配对秘密。
- 邀请使用 128/256 位随机秘密，5 分钟过期且只能消费一次。
- 桌面私钥保存到系统凭据库；HarmonyOS 私钥优先保存到 HUKS。
- SQLite/RDB 只保存加密后的敏感字段和必要索引。
- 设备移除必须进入 revoked 状态，并触发空间密钥轮换流程。
- 网络消息必须限制帧大小、字段长度、batch 数量和处理时间。
- SQL/RDB 查询使用参数绑定，不拼接用户输入。
- 错误消息面向用户时可以说明动作和错误类型，但不能包含密钥、邀请、正文或完整网络帧。

### 签名和本机配置

`harmony/build-profile.json5` 当前属于本机签名配置，可能包含证书路径和受保护密码字段。处理该文件时遵守：

- 不在聊天、日志、文档、测试快照或错误输出中展示 `material` 内容。
- 不提交 `.p12`、`.p7b`、`.cer`、私钥、密码或本机绝对路径。
- 首次提交 HarmonyOS 工程前先完成签名配置脱敏策略：本机忽略、模板文件或 CI secret 三选一。
- 不复制 EggDoneHarmony 的签名配置。
- 不提交 `local.properties`、`.hvigor/`、`.idea/`、`oh_modules/`、构建产物和模拟器数据。

## 编码规范

- TypeScript 和 ArkTS 使用严格类型，不使用无说明的 `any`。
- Rust 正常业务路径不使用 `unwrap()` 或 `expect()`；启动期不可恢复配置错误可以带上下文终止。
- 所有跨端数据结构使用明确的序列化名称和版本。
- 时间持久化为 UTC 毫秒；用户界面按本地时区展示。
- 标识符和代码注释使用英文；用户界面和面向用户的错误使用简体中文。
- 注释解释安全假设、平台限制和非显然决策，不复述代码。
- 保持模块职责单一；只有在消除真实重复或建立测试边界时才增加抽象。
- 不提交无关格式化、临时调试代码、抓包或真实剪贴板样本。

## UI 与 IP

- 延续 EggDone 的蛋黄色、暖黑/米白背景、大圆角和低干扰卡片风格。
- 使用 EggClip 自有图标和原创蛋黄角色，不使用 Gudetama、蛋黄哥、Sanrio 或其他商业 IP 的名称、素材和轮廓复刻。
- 桌面面板保持轻量，不引入大型 UI 框架。
- HarmonyOS 使用 ArkUI 原生组件；安全组件 `PasteButton` 不能用普通按钮伪装。
- 动画必须尊重系统减少动态效果设置，不能阻塞剪贴板或数据库操作。
- 连接失败、离线、认证失败和同步暂停应显示不同状态，不能统一显示“同步失败”。

## 验证要求

### 桌面端

桌面工程生成后，提交前至少运行：

```powershell
cd D:\Develop\eggclip\desktop
pnpm check
pnpm test
pnpm build
cd src-tauri
cargo fmt -- --check
cargo check
cargo test
```

涉及托盘、剪贴板、网络或系统凭据库时，还要用 `pnpm tauri dev` 做 Windows 真机验证。

### HarmonyOS

```powershell
cd D:\Develop\eggclip\harmony
$env:JAVA_HOME = 'C:\Program Files\Huawei\DevEco Studio\jbr'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' test --no-daemon
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon
```

涉及 mDNS、WebSocket、PasteButton、Pasteboard 或 HUKS 时，模拟器结果不能代替真机验收。

### 跨端协议

- Rust 和 ArkTS 必须消费同一组测试向量。
- 至少覆盖成功握手、错误密钥、过期邀请、重放、乱序、重复消息和超限帧。
- 协议变更必须运行 Rust ↔ Rust 和 Rust ↔ ArkTS 互通测试。

## 变更原则

- 按 TODO 阶段推进；除阻断缺陷外，不跨阶段堆叠功能。
- 保持修改聚焦，保护用户已有改动。
- 新增数据库字段必须提供可重复 migration 和升级测试。
- 修改用户可见行为时同步更新 README、对应 TODO 和手动回归清单。
- 修改协议或安全假设时同步更新 `docs/EggClip最佳实现方案.md`。
- 不自动提交、推送、创建分支或发布安装包，除非用户明确要求。
- 不加入遥测、崩溃上报、云同步、自动更新或公网中继，除非另行设计并获得确认。

