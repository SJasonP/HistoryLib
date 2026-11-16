# HistoryLib Android 开发规格

状态：开发基线；Android 不包含在 Apple v1.4 发布中。

目标版本：后续 Android 正式版本，版本号与发布日期另定。

最低系统：Android API 36
本文沿用早期 1.4 开发计划的章节编号和格式要求，不代表 Android 已发布或已完成跨平台验收。
当前发布范围以 `shared/specs/versioning-and-release.md` 为准；Apple 专属增强不自动成为 Android 的已实现功能。

## 1. 文档目的

本文记录已经确认的 Android 产品要求、平台策略和技术方向，用于指导实现、测试、审查和发布。Android 客户端不是独立产品，也不是 Apple 客户端的功能精简版。

规范优先级如下：

1. `shared/specs` 中的跨平台产品与格式契约。
2. 本文的 Android 实施要求。
3. Apple 1.3 已发布行为，用作尚未写入共享契约时的兼容基线。
4. Android 原生设计规范，用于不改变产品语义的视觉和交互决策。

如果 Android 的实现便利性与跨平台语义冲突，应当调整 Android 实现，不得静默改变产品行为。

## 2. 已确认的产品决策

| 项目 | 决策 |
|---|---|
| 产品关系 | Apple、Android、Windows 是同一个 HistoryLib 产品 |
| 仓库 | 三端位于同一个 Git monorepo，不建立嵌套仓库 |
| 首次 Android 正式版本 | 待确定，不包含在 Apple v1.4 中 |
| 发布范围 | Apple v1.4 仅发布 Apple 客户端，Android 与 Windows 后续另定 |
| Android 最低系统 | API 36，故意只支持最新 Android 平台 |
| Android 语言 | Kotlin |
| Android UI | Jetpack Compose + Material 3 |
| 原生要求 | 不使用 Flutter、React Native 或 Kotlin Multiplatform UI/运行时代码 |
| 功能范围 | 除设计、布局和确切的平台技术限制外，三端功能与行为必须一致 |
| 备份 | HistoryLib 不提供备份功能；Android 系统 Auto Backup 关闭 |
| 导出定位 | 导出是用户主动发起的数据转移，不称为备份 |
| 同步模型 | 平台内同步；特定平台在技术复杂时可文档化地不提供同步（详见 `shared/specs/sync.md`） |
| 版本号 | 用户可见产品版本统一；平台内部构建号可以不同 |
| Android 应用 ID | `com.sjasonp.historylib` |

当前工程使用 `minSdk = 36`、`targetSdk = 37`、`compileSdk = 37`。最低系统是明确的产品决策；编译和目标 SDK 可随开发工具更新，但不得未经产品决策降低最低系统。

## 3. 后续正式版本的功能基线

后续 Android 正式版本应覆盖本文的功能基线，并遵循届时的共享规范和发布范围。
开发期间可以分阶段实现，但内部阶段不代表正式发布或完整兼容性验收。

正式发布至少包括：

- Safari 历史记录智能导入。
- Google Takeout Chrome 历史记录智能导入。
- HistoryLib `.hlz` 普通与密码保护归档导入。
- 文件、文件夹和 ZIP 容器处理。
- 年、月、日目录浏览与记录数量。
- URL 和标题搜索。
- 使用系统默认浏览器打开记录。
- favicon 获取、显示、缓存和清理。
- Summary 快照。
- Safari 兼容 ZIP 导出。
- HistoryLib `.hlz` 普通与密码保护归档导出。
- 完全一致的 URL 规范化、去重容差、元数据与访问次数合并规则。
- 单条删除、按时间范围批量删除和破坏性确认。
- 缓存空间测量与清理。
- 与共同产品语义一致的同步状态和控制（仅限实现同步的平台；未实现同步的平台按 `shared/specs/sync.md` 显示明确的不支持状态）。
- 英文、简体中文、阿拉伯语、法语、俄语和西班牙语。
- 手机、平板、折叠屏和可变窗口的原生自适应布局。
- 导入导出进度、取消、错误和结果报告。

## 4. Android 原生技术栈

计划采用以下组件：

- Kotlin：所有产品源代码。
- Jetpack Compose：声明式原生 UI。
- Material 3：Android 视觉、控件与交互语言。
- Navigation Compose：页面和顶层目的地导航。
- ViewModel + StateFlow：屏幕状态管理。
- Kotlin Coroutines + Flow：异步操作和响应式数据流。
- Room：本地结构化历史数据库。
- Paging 3：大型记录列表和搜索结果分页。
- DataStore：用户设置。
- Hilt：依赖注入，包括 ViewModel、Repository 和后台任务依赖。
- Kotlin Serialization：JSON、JSONL、manifest 和索引模型。
- Storage Access Framework：文件、目录选择与导出位置。
- WorkManager 与前台任务执行器：需要离开当前页面后继续的长任务。
- libsodium 原生绑定：兼容现有 HLZENC 的 Argon2id 与 XChaCha20-Poly1305 secretstream。
- Android Keystore：仅用于 Android 本地秘密；不得改变 `.hlz` 密码协议或生成设备绑定的跨平台归档。

依赖版本集中维护在 Gradle version catalog 中，业务代码不得散落硬编码版本号。

## 5. Android 模块结构

目标结构：

```text
platforms/android/
├── app/
├── core/
├── transfer/
├── docs/
├── gradle/
├── settings.gradle.kts
└── build.gradle.kts
```

### `app`

负责 Android 应用壳与平台交互：

- Activity 和 Compose 应用入口。
- Material 3 theme。
- Navigation Compose。
- Summary、Library、Manage、Settings 和 Help 页面。
- ViewModel 与 UI state。
- Storage Access Framework launcher。
- Room entity、DAO、database、migration 和 Repository 实现。
- DataStore 设置实现、favicon 网络/缓存实现和 Android 同步实现。
- 系统浏览器打开、通知、前台任务和 Android 生命周期连接。

### `core`

负责平台无关的契约、模型和纯业务逻辑。`core` 不得 import Android、androidx
或 `:transfer` 类型（此边界由根工程 `checkArchitecture` 强制）：

- Repository、设置、同步和 favicon 的接口契约。
- 持久化历史记录、Summary、ImportRun 和目录数量的逻辑模型。
- URL 规范化和去重规则。
- Summary 计算。
- 时间目录分组与数量统计的纯逻辑。

Room、DataStore、网络和 Android 系统适配属于 `app` 的实现细节，通过 `core`
契约暴露；这与 `ARCHITECTURE.md` 和根工程 `checkArchitecture` 保持一致。

### `transfer`

负责可以独立测试的数据传输协议：

- 输入内容识别。
- Safari 导入器。
- Chrome Takeout 流式导入器。
- HistoryLib `.hlz` 导入器和导出器。
- Safari 兼容导出器。
- ZIP 安全处理。
- JSONL 分块读写。
- manifest、索引、SHA-256 校验。
- HLZENC 加密与解密。

`transfer` 不得依赖 Compose、Activity 或 ViewModel。文件来源通过流或抽象数据源传入，Android `ContentResolver` 适配放在 `app` 或 Android 数据边界中。

## 6. 状态与数据流

Compose 页面遵循单向数据流：

```text
用户操作
  → ViewModel event
  → Repository / use case
  → Room、DataStore、传输服务或系统接口
  → Flow / StateFlow
  → 不可变 UiState
  → Compose 重绘
```

要求：

- ViewModel 不直接持有 Activity、View 或可变 Compose 状态。
- 可复用 composable 不拥有屏幕级 ViewModel。
- I/O、解析、校验、哈希和数据库批处理不得运行在主线程。
- 旋转、窗口尺寸变化和 Compose 重组不得重启导入导出任务。
- 进度和取消状态必须从任务状态恢复，而不是只存在于当前页面。

## 7. 数据模型

Room 主记录应覆盖 Apple `Item` 的全部字段：

公共逻辑模型与时间语义以 `shared/specs/history-record.md` 为准。

```text
HistoryItemEntity
├── id
├── uniqueKey
├── url
├── title
├── visitedAtUsec
├── visitCount
├── sourceBrowser
├── sourceFileName
├── rawTimeUsec
├── sourceURL
├── sourceTimeUsec
├── destinationURL
├── destinationTimeUsec
├── latestVisitWasHttpGet
└── importedAtUsec
```

要求：

- 跨平台真实时间使用 UTC Unix 微秒 `Long` 保存，不得只保存 Android 毫秒时间。
- `visitedAtUsec` 和 `uniqueKey` 必须有索引。
- `uniqueKey` 在 Apple 1.3 中是普通索引，不是数据库唯一约束；Android 不得仅依赖唯一约束替代合并逻辑。
- `visitCount` 最小为 1。
- 可选重定向和 HTTP GET 元数据必须无损保存。
- 数据库 schema 从第一版开始提供明确版本号和 migration 测试。

还应包括：

- `SummarySnapshotEntity`：生成时间、记录总数、日/月/年平均值和 Top Sites。
- `ImportRunEntity`：来源、识别格式、状态、进度、扫描数、有效文件数、导入数、跳过数和失败信息。
- 设备本地的目录数量缓存元数据：记录总数、时区、缓存版本和生成时间。

缓存不是历史数据本身，删除或重建缓存不得改变历史记录。

## 8. 去重合同

Android 必须逐项复现 Apple 1.3 去重行为：

本节是 Android 映射说明；公共规范以 `shared/specs/deduplication.md` 为准。

1. 去除 URL 首尾空白。
2. scheme 与 host 转为小写。
3. 移除 fragment。
4. 移除 HTTP `:80` 和 HTTPS `:443` 默认端口。
5. 空 path 规范成 `/`。
6. 非根路径移除末尾 `/`。
7. browser name 去除首尾空白并转为小写。
8. 时间向下取整到 Unix 秒。
9. 签名为 `normalizedURL|visitedSecond|normalizedBrowser`。
10. 默认启用正负 1 秒近似重复容差。
11. 重复项不新增记录，而是把 `visitCount` 相加。
12. 合并时保留更丰富元数据的规则必须与共同测试一致。

同一规则用于：

- Safari 导入。
- Chrome 导入。
- `.hlz` 导入。
- 同步后的后台清理。

不得在每个导入器中分别维护一套 URL 或去重实现。

## 9. 顶层导航与自适应布局

顶层目的地固定为：

- Summary
- Library
- Manage

手机使用 Material 3 bottom navigation。Library 内提供搜索，搜索不是另一份数据库或独立产品功能。

较宽窗口使用 Navigation Rail。Library 可使用目录/记录列表的双栏或自适应 pane，但必须保留相同的筛选、分页、展开和操作语义。窗口变宽时不得只是把手机单栏无限拉伸。

Android 不复制 Apple 的 Liquid Glass、TabView 或 toolbar 外观。图标、触控区域、返回行为、预测性返回、对话框和系统栏遵循 Android 原生规范。

## 10. Summary

Summary 页面显示：

公共统计语义以 `shared/specs/summary.md` 为准。

- Total Records。
- Average Per Day，保留两位小数。
- Average Per Month，保留两位小数。
- Average Per Year，保留两位小数。
- Top 10 Most Visited Sites。
- Last Modified。
- 无数据时的空状态。

在共同语义正式修改前，Android 必须匹配 Apple 1.3：

- 总数和平均值按存储记录数量计算。
- Top Sites 对每条存储记录累计 1，而不是对 `visitCount` 求和。
- 时间跨度和 host 提取规则必须使用共享 fixtures 验证。

如果未来要把统计改成真实访问次数，必须作为三端共同产品变更，不能由 Android 单独修正。

## 11. Library 与搜索

Library 要求：

- 记录按时间倒序显示。
- 目录按年、月、日分组。
- 年、月、日显示记录数量。
- 默认展开级别支持不展开、年、月、日。
- 分组折叠后释放不再需要的记录页和加载任务。
- 单日记录使用分页加载，不一次性读取整个数据库。
- 可选择显示 `HH:mm:ss`。
- 可选择显示 favicon。
- 点击是否打开链接受设置控制。
- 删除功能未启用时，不出现误触删除入口。

搜索要求：

- 搜索 URL 或标题。
- 去除查询首尾空白。
- 匹配行为等同本地化、不区分大小写的 contains。
- 输入 debounce 约 250 ms。
- 结果按访问时间倒序。
- 分页扫描不能静默跳过一个扫描批次中超过页面大小的匹配项。
- 新查询取消旧查询，旧结果不得覆盖新结果。
- 大数据集搜索不能阻塞主线程。

如使用 SQLite FTS 优化，必须先证明其分词、标点、URL 和本地化行为与上述 contains 语义等价；否则使用索引、分批扫描或额外规范化字段实现。

## 12. 智能导入

### 唯一入口

Manage 页面只提供一个 `Import` 产品入口，不提供 Safari、Chrome、HistoryLib 格式选择器。

公共导入与浏览器格式规范见 `shared/specs/smart-import.md` 和 `shared/specs/browser-history-formats.md`。

由于 Android 系统选择文件和选择目录使用不同机制，点击 Import 后可以出现原生选择：

- 选择文件。
- 选择文件夹。

这只是输入位置选择，不是格式选择。

### 内容识别顺序

识别必须基于内容，而不是文件名或扩展名：

1. HistoryLib 普通或加密归档。
2. Safari 历史记录。
3. Chrome Takeout 历史记录。
4. 其余输入拒绝。

Safari 在 Chrome 前探测，因为二者都可能使用 `History.json` 文件名。

未知 JSON、ZIP、文件夹或其他输入必须在插入任何历史记录前报告“不支持的格式”。不得把未知内容默认当成 Safari。

### 输入来源

- 单个 JSON 文件。
- ZIP 文件。
- `.hlz` 文件。
- 用户选择的目录树。
- 来自本地存储、云端 DocumentsProvider 或 USB 的 `content://` URI。

不得要求广泛文件系统权限。需要跨任务读取时，使用持久 URI 权限或把内容安全复制到应用临时目录。

### 执行行为

- Chrome `Browser History` 数组必须流式解析。
- 大文件不得完整加载到内存。
- 数据按固定批次写入 Room。
- 进度支持未知总量和已知总量两种状态。
- 用户可以取消。
- 结果报告格式、扫描文件数、有效文件数、导入数、跳过数和逐文件失败。
- 文件夹中的单个无效候选文件按 Apple 行为形成失败报告；整个输入无法识别时则完全拒绝。
- 密码保护归档需要原生密码输入页面；密码只保留在当前任务内。

## 13. ZIP 与输入安全

所有 ZIP 或目录输入必须防护：

- 绝对路径。
- `..` 路径穿越。
- 符号链接或规范化后逃离临时根目录。
- 重复关键条目。
- 非法 chunk path。
- 条目数量、单条大小和总解压大小失控。
- 异常压缩膨胀。
- JSON 深度或单记录大小失控。
- Int64 时间溢出。
- checksum、记录数和 manifest 不一致。

临时明文只能位于应用私有目录，必须在成功、失败和取消后清理。日志不得输出完整 URL、标题、密码或记录载荷。

## 14. HistoryLib `.hlz` 兼容

Android 必须读写与 Apple 完全兼容的 `.hlz` v1。规范见 `shared/specs/hlz-v1.md`，它是三端唯一的归档格式定义。

必须保持：

- ZIP 容器。
- `manifest.json`。
- 有序 JSONL chunks。
- `indexes/chunks.json` 与 SHA-256。
- 年、月、日建议索引。
- 可选 summary snapshot。
- UTC Unix 微秒。
- 空归档规则。
- 未知字段向前兼容规则。
- 验证完成后才信任和导入 chunk。

密码保护归档必须保持：

- `HLZENC` v1 固定头。
- 密码 Unicode NFC 规范化与 UTF-8 编码。
- Argon2id 1.3。
- 32 字节密钥。
- 16 字节随机 salt。
- operations limit 2。
- memory limit 64 MiB。
- 1 MiB 明文消息。
- XChaCha20-Poly1305 secretstream。
- 24 字节 secretstream header。
- big-endian 长度字段。
- 固定头作为每条消息的附加认证数据。
- 最后一条必须为 `FINAL`。
- 错误密码和损坏密文不向用户泄露不同认证细节。
- 拒绝缺失或重复 FINAL、乱序、篡改、尾随字节和越界参数。

Android 与 Apple 必须使用同一批普通、加密、损坏和篡改 fixtures 进行双向导入导出测试。

## 15. 导出

Manage 页面支持两种格式：

### HistoryLib

- 只提供一个优化 `.hlz` 归档布局。
- 密码可选。
- 输入密码后必须再次确认。
- 两次密码不一致时不得导出。
- 密码经过 NFC 规范化后参与比较和加密。
- 少于 12 个字符时警告，但允许用户明确选择继续。
- 密码不保存，不提供恢复。

### Safari

- 单文件。
- 每年一个文件。
- 每月一个文件。
- 每日一个文件。

Android 使用 Storage Access Framework 让用户选择目标位置。准备、导出和打包阶段必须提供进度及取消；生成失败或取消后清理临时文件，不留下看似成功的半成品。

## 16. Manage、删除与缓存

Manage 至少包括：

- Import。
- Export 格式与布局。
- 同步检查。
- Clear Cache。
- 启用删除后显示 Batch Delete。
- Help。

批量删除：

- 默认范围为最早到最新记录。
- 开始时间不得晚于结束时间。
- 时间变化后 debounce 再计算匹配数量。
- 最终按钮显示准确记录数量。
- 执行前显示不可撤销确认。

Clear Cache：

- 先计算可清理缓存和不可清理数据空间。
- 明确说明不会删除历史记录、Summary、导出文件或同步数据。
- 删除 favicon 文件、favicon 内存状态、临时目录和目录数量缓存。
- 取消正在进行的 favicon 请求，防止清理后立刻重新写回。
- 如果用户选择同时关闭 favicon，则更新对应设置。

## 17. 设置

Android 设置必须提供与 Apple 等价的语义：

- Show Visit Time，默认开启。
- Show Site Icons，默认开启。
- Default Expand To，默认 Day。
- Enable Deletion，默认关闭。
- Enable Sync，默认关闭；最终名称随共同同步方案确定。
- Open Link On Tap，默认开启。

设置使用 DataStore 持久化。所有用户可见标题、说明和动态消息进入 Android 原生字符串资源，并提供六种产品语言的翻译。

## 18. favicon 与网络隐私

启用 favicon 时可以：

- 访问记录 URL 或站点根页面发现 icon link。
- 尝试 `/favicon.ico`。
- 尝试 `/apple-touch-icon.png`。
- 尝试 `/apple-touch-icon-precomposed.png`。
- 校验响应确实是可解码图片。
- 缓存成功结果和短期失败结果。

设置说明必须告知用户：请求 favicon 可能向目标服务器暴露访问过的域名。关闭 favicon 后不得继续发起新请求。

## 19. 同步

已确认共同决策：HistoryLib 1.4 采用 **平台内同步**。公共状态与决策边界见 `shared/specs/sync.md`。

- 各平台只在自己的生态内同步：Apple 使用 iCloud，Android 使用 Android 原生同步方案（若实现），Windows 使用 Windows 原生同步方案（若实现）。
- 1.4 不提供跨平台共享数据服务；跨平台同步不在本版本范围内。
- 如果平台内同步在某个平台上技术过于复杂，该平台可以文档化地不提供同步，但必须显示明确的“不支持同步”状态，不得展示可启用却不可用的假同步，不得声称功能对齐，也不得把备份或仅本地存储当作同步。

**Android 当前同步决策：不提供同步。** Android 端以明确的“不支持同步”
状态发布（`UnsupportedSyncService`），不展示可启用却不可用的假同步，也不声称
同步功能对齐。这是已文档化的平台限制，记录在
`shared/specs/product-parity.md`。

Android 的实现要求：

- 如果实现同步，Android 需要提供与 Apple iCloud 等价的启用、状态、重试、不可用处理和数据一致性保护。
- 数据层必须通过 `SyncService`/Repository 抽象隔离具体提供方。
- 不得把 Android Auto Backup 当成同步实现。
- 不得通过同步整个 Room 数据库文件实现记录同步。
- 不得为了先完成 Android 而删去 Apple 已有的同步状态、检查和写保护语义。
- 如果 Android 在 1.4 选择不提供同步，必须在设置与 Help 中明确说明同步在该平台不可用，并在 Android 文档或 `shared/specs/product-parity.md` 中记录为已文档化的平台限制。

## 20. 无备份政策

HistoryLib Android 不提供产品级备份：

- Manifest 设置 `android:allowBackup="false"`。
- 不提供 Backup 页面。
- 不生成定时 `.hlz`。
- 不把导出宣传为备份。
- 不依赖 Android Auto Backup 恢复 Room 数据。

用户仍可主动导出 `.hlz` 或 Safari ZIP，并自行保存或传输文件。同步与导出均不称为备份。

## 21. 后台执行、进度与取消

短任务可以在应用进程内使用协程。导入、导出、校验、加密、缓存重建和大规模去重必须经过统一任务层，能够：

- 在页面重建后恢复状态。
- 显示当前阶段、消息和可用时的比例。
- 提供取消。
- 串行化会竞争同一数据库或临时文件的破坏性任务。
- 在后台执行受系统限制时提供明确反馈。
- 记录结构化错误，但不记录敏感载荷。

是否使用 WorkManager、前台服务或二者组合由任务持续时间和 Android API 36 行为决定；UI 不得直接依赖具体调度器。

## 22. 本地化与无障碍

- 产品语言为英文、简体中文、阿拉伯语、法语、俄语和西班牙语。
- 不在 Kotlin 或 composable 中硬编码用户可见文字。
- 动态数量、日期和错误消息必须本地化。
- 日期时间使用用户 locale 和时区显示，存储仍使用 UTC 微秒。
- 图标按钮提供 content description。
- 触控目标、TalkBack 顺序、颜色对比和大字体布局必须通过检查。
- 密码框不得通过可访问性、日志或状态恢复泄露明文。

## 23. 测试与验收

### 纯 JVM 测试

- 内容识别。
- Safari/Chrome 流式解析。
- URL 规范化。
- 精确和近似去重。
- metadata 与 `visitCount` 合并。
- Summary 计算。
- JSONL 和 manifest 编解码。
- SHA-256。
- HLZENC test vectors。
- 错误输入和资源限制。

### Room 与 Android 集成测试

- schema migration。
- 大批量事务和取消。
- Paging 顺序与不漏项。
- 搜索 contains 语义。
- 时间范围删除。
- 时区变化后的目录缓存失效。
- `content://` 文件和目录访问。
- 进程重建后的任务状态。

### Compose 测试

- 三个顶层目的地。
- Import 单一入口。
- 文件/文件夹选择而非格式选择。
- 密码确认和弱密码警告。
- 删除开关和最终确认。
- 空状态、错误状态和进度状态。
- 六种产品语言、阿拉伯语从右到左布局和大字体。

### 跨平台互操作

- Apple 导出普通 `.hlz`，Android 导入。
- Android 导出普通 `.hlz`，Apple 导入。
- Apple 导出加密 `.hlz`，Android 导入。
- Android 导出加密 `.hlz`，Apple 导入。
- Android 生成的 Safari ZIP 能被 Apple 重新导入。
- 未知 JSON/ZIP 在三端都拒绝且零写入。
- checksum 错误、篡改、截断和错误密码在三端都失败。
- 时间、`visitCount` 和可选元数据往返后不丢失。

### 性能基线

至少使用 10 万和 100 万条虚构记录检查：

- 峰值内存受控。
- 导入导出不阻塞主线程。
- Library 首屏、展开和分页可用。
- 搜索不会漏结果。
- Summary 和缓存重建可以取消。

具体时间和内存阈值应在获得目标 API 36 设备基准后写入 CI 或性能文档，不在没有测量前编造数字。

## 24. 内部实施顺序

以下是开发顺序，不是可分别发布的产品版本：

1. Compose 应用入口、Material 3 theme、导航和 DataStore。
2. Room schema、Repository、Paging 和共享数据模型映射。
3. 智能导入、Safari、Chrome 和普通 `.hlz`。
4. Library、搜索和 Summary。
5. 导出、删除、缓存和设置。
6. 加密 `.hlz` 双向互操作。
7. favicon、Help、本地化和自适应布局。
8. 同步实现。
9. 跨平台 fixtures、性能、无障碍和发布验收。

内部阶段不作为正式版本发布；后续发布应按确定的范围完成实现和验收。

## 25. 完成定义

后续 Android 正式版本需要完成以下要求：

- 本文所有非待定功能已经实现。
- 同步决策已经解决（平台内同步），Android 已按第 19 节实现同步，或已按 `shared/specs/sync.md` 文档化地放弃同步并显示明确的不支持状态。
- `shared/specs/product-parity.md` 中的要求全部满足。
- Android 单元、集成、Compose、lint、Debug 和 Release 构建通过。
- Apple 与 Android 的普通和加密 `.hlz` 双向互操作通过。
- 六种产品语言完整。
- API 36 真机完成大数据、后台、取消、存储和无障碍验证。
- Android 用户可见版本与其正式发布计划一致。
- 完成该次发布范围内的兼容性和验收要求。
