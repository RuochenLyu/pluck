# 产品方案：macOS 原生开源 Remove BG 应用

> 2026-07-27。前置调研见 [removebg-research.md](removebg-research.md)。

## 1. 产品定义

一句话：**完全离线的 macOS 原生抠图工具——拖进来、抠出去，照片从不离开你的 Mac。免费、开源、还能被 AI agent 调用。**

三条产品原则（对应需求）：

1. **不联网、隐私好、免费**——默认路径零网络请求（模型下载除外，且是用户显式触发）；代码开源可审计。
2. **UI 好、交互好**——原生 SwiftUI，拖拽 / Finder 右键 / 剪贴板全链路，模型可扩展但默认零配置。
3. **CLI + Agent skill**——同一个引擎暴露为命令行工具和 agent skill，是**第一个明确面向 AI agent 设计的抠图工具**（差异化卖点，现有竞品全部没有）。

## 2. 命名

已排除（撞名严重）：Peel/Peeler、Cutout、ClearCut、Kirigami（KDE 框架）、PaperCut（打印软件）、Lift（多个）。

候选（发布前需再做一次商标/App 名复查）：

| 候选 | 理由 | CLI 观感 |
|---|---|---|
| **Pluck**（推荐） | "把主体拔出来"，动词、短、好记、好读；GitHub/domain 空间干净 | `pluck photo.jpg` ✅ 极自然 |
| Pare | "削掉外皮"，同样短小的动词 | `pare photo.jpg` ✅ |
| Kirie | 切り絵（日式剪纸），有美感、独特 | `kirie photo.jpg` 稍难拼 |
| Matteless | alpha matte 梗，专业感 | 偏长 |

推荐 **Pluck**：动词即用法，app 和 CLI 共用一个心智——"pluck the subject out of the photo"。品牌语：*"Pluck — lift subjects out of photos. Offline, free, open source."*

## 3. 卖点（README/官网首屏顺序）

1. **100% 离线**——你的照片从不离开这台 Mac。无账号、无上传、无遥测，开源代码可验证。
2. **秒出结果**——系统级模型（与 Finder「移除背景」同源），无需下载任何东西，装完即用。
3. **原生体验**——标准单窗口：拖入/⌘V（位图粘贴即抠即回剪贴板，不落盘闭环）、before/after 对比 inspector、逐图换引擎、网格/列表双视图、批量进度；Finder 右键（规划中）。
4. **可扩展的高质量模式**——按需下载 MIT 协议的高精度模型（发丝级边缘），不满意随时切回。
5. **为 AI agent 而生**——自带 CLI 和 agent skill，Claude Code / 任何 agent 一行命令抠图。
6. **免费，永远免费**——没有订阅、没有"预览高清下载低清"、没有水印。

第 1、5 条是竞品完全没有的组合；第 6 条直接踩中调研里最大的用户怨气（订阅陷阱 + bait-and-switch）。

## 4. 技术架构

### 4.1 仓库结构（Swift Package 单仓）

```
pluck/
├── Sources/
│   ├── PluckKit/            # 核心引擎库（无 UI 依赖）
│   │   ├── MattingEngine.swift      # protocol：CGImage → mask/合成
│   │   ├── VisionEngine.swift       # 默认：VNGenerateForegroundInstanceMaskRequest
│   │   ├── CoreMLEngine.swift       # 加载任意 .mlpackage 的通用推理
│   │   ├── ModelRegistry.swift      # 模型清单、下载、校验、存储管理
│   │   └── Compositor.swift         # mask → 透明 PNG / 纯色 / 自定义背景合成
│   ├── PluckCLI/            # 命令行（swift-argument-parser）
│   └── PluckApp/            # SwiftUI app（单窗口：toolbar + 网格/列表 + 预览 inspector）
├── Extensions/
│   └── FinderQuickAction/   # Action Extension（右键「Pluck 移除背景」）
├── skills/
│   └── pluck/SKILL.md       # agent skill，随仓库分发
├── models/manifest.json     # 可下载模型清单（名称/URL/SHA256/license/体积）
└── homebrew/                # cask (app) + formula (cli)
```

核心设计：**PluckKit 是唯一引擎，App、CLI、Finder 扩展都是它的薄壳。** 保证三个入口行为一致，也让第三方能直接依赖 PluckKit。

"薄壳"由 PluckKit 的入口 API 界定——壳只负责 I/O、命名、进度与错误呈现，从字节到合成图之间的一切归 PluckKit：

```swift
public enum PluckSource { case file(URL), data(Data), image(CGImage) }

public struct PluckPipeline {                        // load → mask → compose
    public init(engine: any MattingEngine = VisionEngine(), background: PluckBackground = .transparent)
    public func run(_ source: PluckSource) async throws -> PluckRun
}

public struct PluckRun {                             // 中间态一并保留，不必重算
    public let input: CGImage                        // 已应用 EXIF 方向的输入 = before
    public let mask: CGImage
    public let image: CGImage                        // 合成结果 = 导出物
    public func pngData() throws -> Data
}

public enum Thumbnail {                              // 按长边降采样，供 UI 使用
    public static func fit(_ image: CGImage, maxEdge: Int) throws -> CGImage
    public static func pngData(for image: CGImage, maxEdge: Int) throws -> Data
}
```

### 4.2 引擎层

```swift
protocol MattingEngine {
    var id: String { get }          // "vision" / "birefnet-lite" / ...
    func mask(for image: CGImage) async throws -> CGImage   // 灰度 mask
}
```

- **VisionEngine（默认）**：`VNGenerateForegroundInstanceMaskRequest`，macOS 14+，零体积。处理三个已知边界：空 mask（报"未检测到主体"而非崩溃）、>50MP 先降采样再抠、多主体合并 mask 照常输出。
- **CoreMLEngine（扩展）**：通用 mlpackage 推理壳（前处理 resize/归一化 + 后处理 mask 放大回原尺寸）。模型扩展 = 往 manifest 加一条记录，不改代码。
- **首发扩展模型**：BiRefNet_lite（MIT）自转 Core ML，INT8 量化目标 <150MB；托管在 GitHub Releases 或 Hugging Face，下载后 SHA256 校验，存 `~/Library/Application Support/Pluck/Models/`。
- 合成输出：透明 PNG（默认）、纯色/自定义背景、仅 mask。边缘做轻量 decontamination（去背景色渗透）——这是 Pixelmator 口碑最好的点，值得在 Compositor 里做（v1.0 项）。
- 实现注（2026-07-27）：背景类型用自定义 `PluckBackground`（`.transparent`/`.solid(PluckColor)`）而非 `CGColor`，保证 `Sendable` 与 sRGB 语义明确；合成走显式逐像素预乘 alpha 循环而非 `CGImage.masking`（后者语义不可测试到字节级）。

### 4.3 App 交互（全部走 PluckKit）

> **2026-08-10 重定稿（见 decisions.md 同日）**：本节此前的"菜单栏 shelf / 状态项 / 预览浮窗 / presence 开关"全部作废。现行形态：**纯 Dock app，一个标准窗口**——`.titled` + unified toolbar（Add / 默认引擎菜单 / Preview / Export），内容区为不透明标准背景上的卡片网格，**预览是 `.inspector` 侧栏**（before/after 滑块、引擎切换、拷贝/存储/删除），单击选中即更新、双击或工具栏按钮打开。入口：拖入窗口、拖 Dock 图标、⌘V、Finder 打开方式；批量进度走 `navigationSubtitle`。Settings 为标准两 tab（General / Models）。以下原文仅作历史记录保留。

- ~~**形态：Dock app + 可选菜单栏（2026-07-29 定案，见 decisions.md 同日）**。~~默认 `.regular`：有 Dock 图标、启动即开主窗口、点 Dock 图标开主窗口、**Dock 图标接受拖图**（`CFBundleDocumentTypes` public.image / Viewer / Alternate → `application(_:open:)` → 同一条 `handleDrop` 管线，多文件一次进批量）。Settings ▸ 通用两个开关：`Show Pluck in the menu bar`（默认开，关=移除状态项）与 `Hide the Dock icon`（仅前者开启时可用，开=运行时 `setActivationPolicy(.accessory)`，即原来的形态）。两开关不得同时导致"无处可点"，不变式在 `Preferences` 内。**这条推翻此前"菜单栏为主入口"的定位**：Pluck 是任务式处理器（ImageOptim / Permute 那一类），不是常驻监听器。
- **菜单栏常驻**（菜单栏图标开启时，行为不变）：**拖到图标是拖放的主路径**——拖入时图标变实心 + 珊瑚色，松手即处理并自动弹出面板。点击图标也可打开面板（只打开，不 toggle）。面板是自绘的非激活 NSPanel（不是 NSPopover，容器视觉要自己控），内含 Recent 网格 + Clear，本身也接受拖放但不是承重路径；点面板外任何地方即关，Esc / ⌘W 同。剪贴板流程：面板内 ⌘V → 抠图 → 结果自动写回剪贴板 → 目标 app ⌘V，**中间不落盘**（2026-07-27 起废弃全局快捷键方案）。点击 Recent 项打开预览面板：before/after 拖拽滑块 + Copy/Save。
- **处理中反馈**：Recent 网格头部占位卡（输入图缩略图去饱和 + 扫光，>250ms 才出 spinner，完成原地交叉淡出）；面板关闭时由菜单栏图标呼吸脉冲承担。
- **主窗口**：大拖放区；多文件/文件夹拖入进批量队列，逐张进度 + 失败标记；处理前后对比（滑块）；导出格式与目的地记忆。
- **结果浮层**（CleanShot X 式）：处理完弹小浮层，可直接拖去别的 app / 复制 / 存到指定文件夹 / 换背景色，不强制保存对话框。
- **Finder 右键**：Action Extension 注册 Quick Action，选中多张图右键即批量处理，输出 `xxx.png` 到原目录（可配置）。
- **设置**：默认引擎、模型管理（下载/删除/各自 license 展示）、输出格式、快捷键。默认值全部开箱可用，设置是"出口"不是"门槛"。

### 4.4 CLI（面向人类 + agent 双模式）

```bash
pluck photo.jpg                        # → photo.png（透明背景）
pluck *.jpg -o out/                    # 批量
pluck photo.jpg --model birefnet-lite  # 指定引擎
cat photo.jpg | pluck - > cut.png      # stdin/stdout 管道
pluck photo.jpg --json                 # NDJSON：input/output/width/height/durationMs/engine/ok
pluck models list / pull birefnet-lite # 模型管理
```

agent 友好设计：`--json` 结构化输出、语义化 exit code（0 成功 / 2 未检测到主体 / 3 模型缺失）、无 TTY 时自动关闭进度条、绝不弹 GUI。安装：`brew install pluck`（formula 独立于 app，agent 环境不需要装 app）。

### 4.5 Agent skill

仓库内置 `skills/pluck/SKILL.md`：描述何时用（用户要抠图/透明背景/换背景时）、CLI 用法、JSON 输出解析、常见失败处理。用户 `cp -r` 或 symlink 到 `~/.claude/skills/` 即可。README 单列一节 "Use with AI agents"。MCP server 暂不做——CLI + skill 已覆盖 agent 场景，保持 Unix 式简单。

### 4.6 分发（GitHub，不上 App Store）

- 有开发者账号正好：**Developer ID 签名 + notarization**（GitHub 分发的正确姿势，用户打开无 Gatekeeper 警告）。CI 里用 `xcodebuild` + `notarytool` 自动化。
- **GitHub Releases**：DMG（app）+ 独立 CLI 二进制 + 模型文件。
- **Homebrew**：`brew install --cask pluck`（app）+ `brew install pluck`（CLI），先建自有 tap，star 数够了提交 homebrew-core/cask。
- **Sparkle** 做 app 内自动更新（不联网原则的唯一例外之二：更新检查 + 模型下载，都在设置里可关，README 里明示这两个网络行为——隐私承诺要经得起审计）。
- 不上架的判断没问题：CLI、Sparkle、模型旁加载在 MAS 沙盒下都别扭，GitHub + Homebrew 是这类工具的主流通路（Rectangle、Ice 同款）。

### 4.7 UI 设计定稿（2026-07-27，第二轮原型）

> **2026-08-10 重定稿（见 decisions.md 同日）**：本节的"无边框玻璃面板"体系（四条硬规则的①③④、面板吸色玻璃、主窗口沉浸玻璃、自绘标题区）**作废**。HIG 核实结论：Liquid Glass 属于控件层，窗口与内容背景不做玻璃；玻璃由**标准组件**（toolbar / inspector / 菜单）自动获得，自定玻璃只保留悬浮在图片上的 hover 圆钮。配色回归系统 accent，珊瑚橙只留给 app 图标。卡片语言（实色卡面 + 卡内低对比棋盘格 + `Tokens`）继续有效。以下原文仅作历史记录保留。

定稿图见 [prototypes/](prototypes/)（p1–p6），提示词底稿见 [prototypes/prompts.md](prototypes/prompts.md)。要点：

- **视觉语言**：macOS 26 Liquid Glass，内容/功能分层——抠图结果与棋盘格是内容层不加玻璃；浮层容器、按钮、工具栏是功能层用玻璃。圆角/阴影参数跟随系统，不写死数值。
- **四条硬规则**（2026-07-27 补，从原型反推、App 内所有面板通用）：①内容满铺到容器边缘，禁止 letterbox 灰底；②工具条浮在内容之上用玻璃材质，不用 `Divider()` 分区；③一级操作是无文字圆形玻璃图标按钮，文字按钮只给次要动作；④不用系统标题栏，标题以玻璃胶囊叠在内容左上角。预览类面板尺寸跟随图片长宽比（长边 ≤560pt、短边 ≥320pt）。⑤**从某个面板打开的面板必须叠在它上面**——层级顺序显式声明（shelf = `.popUpMenu`，预览 = `.popUpMenu + 1`），不靠默认值碰运气。
- ~~**玻璃分级**（mockup 的玻璃浓度是上限不是规格）：主窗口用标准窗口材质保可读性（背后可能是任意窗口而非壁纸）；菜单栏 popover 与结果浮层保持强玻璃。~~ **2026-07-28 作废**（见下"主窗口沉浸玻璃"与 decisions.md 同日）：**分级已经取消，全 app 一种玻璃**。深 tint 玻璃本身就是可读性方案（p4 的深紫底就是这么工作的），浓度由 `Tokens` 的 Liquid Glass 参数统一控制，不再按表面分档。
- **视觉语言 v2（2026-07-28，对照 p3 + Dropover/Yoink 重修）**：v0.1 的实现把上面这些规则执行成了"原生组件堆砌"，v2 把差距补上，**只改皮肤不动交互**。四条：①面板吸色玻璃（shelf 背板 `.hudWindow` + `.behindWindow`，不再是近乎不透明的 `.popover`），圆角 20；②**面板内零细线**——所有 `Divider()` / hairline 描边删除，分区只靠留白、圆角与填充（主窗口列表行的分界改为 hover 圆角填充）；③结果格是**卡片**不是洞：白/深灰卡面 + 圆角 14 + 内边距 6，细腻低对比棋盘格（6pt 方格、约 5% 对比）在卡内；④体量上调：圆按钮 32pt、预览工具条 36pt、面板边距 20、Settings 图标砖 36pt。所有数值集中在 `Sources/PluckApp/DesignTokens.swift`（`Tokens`），**改那一个文件 = 改全局**。Settings 仍是"用户会找的窗口"，Form 的原生分组与其自带分隔保留（见上一条玻璃分级）。
- **Liquid Glass 分层（2026-07-28，v2 的补丁）**：v2 说的"玻璃"实际上是 macOS 14 的 `NSVisualEffectView` / `Material`——只模糊，不折射。本机 SDK 起改为**双写**：`if #available(macOS 26.0, *)` 走真玻璃（AppKit `NSGlassEffectView`/`NSGlassEffectContainerView`；SwiftUI `.glassEffect(_:in:)`/`GlassEffectContainer`/`.buttonStyle(.glass)`/`.glassProminent`），以下回落现有材质；两个分支只在形状与尺寸上一致，不用 deprecated API 绕过分层。**边界是分层不是浓度**：容器与控件用玻璃，内容层（cutout、棋盘格、承载它们的卡片）一律实色——透明图后面再模糊一次壁纸，两层透明谁都读不清。三个入口 `pluckGlass` / `GlassGroup` / `PanelBackdrop`（`Sources/PluckApp/Glass.swift`），内容层的代码里不出现它们。逐表面：shelf 与预览面板背板 = `NSGlassEffectView`（圆角由它的 `cornerRadius` 接管，拖放目标拆成独立的普通 `NSView`）；预览工具胶囊 = 一整块透镜 + 裸 glyph，不是三块玻璃；独立站在图片上的圆钮、状态浮条、Original/Cutout 角标 = 各自一块玻璃，成对的用 `GlassEffectContainer` 合并；~~主窗口维持标准窗口材质，只统一控件语言（Export All = `.glassProminent` + 珊瑚）~~（2026-07-28 作废，主窗口现在与 shelf 同一块玻璃，见下条）；Settings 只换按钮样式，Form 原生分组不动；系统菜单不动。26 分支上不再叠 macOS 14 的控件阴影（`Tokens.glassShadow`），`.interactive()` 玻璃自带按下反馈，本地缩放同时停用。
- **主窗口沉浸玻璃（2026-07-28 定案，对照 p4）**：主窗口与 shelf 用**同一块玻璃、同一套 `Tokens` 参数**——26+ 是 `NSGlassEffectView`（`PanelBackdrop`，圆角传 0：`.titled` 窗口的窗缘自己会裁），14 回落 `NSVisualEffectView` `.underWindowBackground` + `.behindWindow`。窗口 `fullSizeContentView` + `titlebarAppearsTransparent` + `backgroundColor = .clear` + `isOpaque = false`；**红绿灯保留**（这是可缩放、会被留在后台的窗口，操作它的部件必须在），**标题文字 `titleVisibility = .hidden`**——菜单栏已经说清身份，玻璃面上一个孤零零的 "Pluck" 是一条忘了画背景的标题栏。`window.title` 仍照常设置并走 catalog（Mission Control、Window 菜单、VoiceOver 用的是它）。内容顶部留 28pt 让开红绿灯，不做"内容滚到红绿灯底下"——没有标题栏材质垫着，滚过去的卡片和三颗按钮之间没有任何东西分隔。**系统底一律删**：滚动区 `.scrollContentBackground(.hidden)`、底栏去 `.bar`、空态去掉 `.quaternary` 洗色**与虚线框**（虚线是面板内细线，v2 早就禁了；整窗即投放目标，拖拽时的 accent 边才是回答）。卡片仍是实色（内容层原则不变）。亮/暗两模式实测通过。
- **强调色**：珊瑚橙每屏至多一个染色元素（主按钮/进度/选中勾），其余中性。
- ~~**图标**：实心有机 blob + 虚线剪影（主体被拽走留下轮廓）；18px 菜单栏版虚线简化为 4–5 段粗 dash，进开发后直接画矢量模板 PDF。羽毛方案废弃。~~ **2026-08-11 定稿替换**（见 decisions.md 同日）：图标 = 珊瑚猫走出照片卡、卡上留猫形洞（cat-1 概念，ImageGen 分层素材）；`Packaging/icon/` 三图层 + `Scripts/make-icon.swift` 合成 icns；Icon Composer 玻璃版（.icon）待做，素材已备。菜单栏图标随 shelf 删除，不再需要。
- ~~**入口层级**：菜单栏为主入口（单张高频场景），主窗口为批量处理场景（保留空状态）。~~ **2026-07-29 作废**（见 §4.3 与 decisions.md 同日）：**主窗口是主入口**，菜单栏 shelf 是单张高频场景的快捷路径。
- ~~**结果浮层**（自动弹出版）~~ 2026-07-28 决定不做（见 decisions.md）：不自动弹，结果由用户点缩略图打开预览面板查看。预览面板保留本节的尺寸与操作设计（Copy/Save、before/after），去掉倒计时。
- **shelf 结构（2026-07-28 定稿）**：无投放横幅、无底栏——面板整体即投放目标；有内容时网格首格为虚线"幽灵格"（+ 与 ⌘V 提示，"下一张落在这里"），空态为同语法撑满版；Clear/主窗口/齿轮菜单并入 RECENT 标题行；状态消息为浮动材质条，仅在有话可说时出现；缩略图右键菜单含单项 Delete。依据：对 Dropover/Yoink/Dropzone 等 12 款 menubar app 的两轮调研（decisions.md 同日）。
- **主窗口 = 图像画廊（2026-07-28 产品审计后定稿，取代原"批量队列"行列表）**：内容区是 `LazyVGrid(.adaptive(132…150))` 的结果卡网格，卡片语言与 shelf 共用同一个 `CutoutCard`（白/深灰卡面 + 卡内棋盘格 + 图满铺卡面），hover 抬起、右上出 Copy/Save 玻璃圆钮、底部浮一条玻璃小字（名称 · 尺寸 · 非默认引擎名；名称先让位截断）。**无常驻投放条**——整窗即投放目标，拖拽悬停时内容区一圈 accent 边；空态保留完整教学。**选择**：单击选中（accent 描边 + 左上角勾圈）、再点取消、⌘点多选、⌘A 全选、Esc 清空、双击开预览、整卡可拖出，右键菜单与 shelf 对齐（Copy Image / Save As… / Show Preview / Delete）。**底栏**：左侧只在有话可说时出状态行（"N cutouts" 计数删除——格子本身就是那些抠图），右侧 Export 按钮说出它真正会写的东西：无选中 "Export All…"、有选中 "Export N…"（复数走 catalog），条目集 = `AppModel.exportTargets`。多图批次的顶部进度条保留；行尾 ✓ Done 取消——占位卡在原格变成结果就是那个 ✓。p2 的 "Waiting" 仍不做：排队与执行的分界在 PluckKit 的 `PluckQueue` 里，猜一个就是给正在处理的图贴静态标签。
- **设置（2026-07-28 定稿，同日验收后修订）**：不做 toolbar tab——一屏放得下的两节不需要一根用来切换它们的工具栏。一个 Form，Models 一节在上，History 一节在下。**选择即行**：删掉单独的引擎 Picker（一个决策两个控件，而能说清"这个引擎是干嘛的"的那个反而不可点），每行最左是珊瑚圆勾选中标记，点行即切默认引擎；未安装的行圆圈灰显不可选。行结构 = 选中圈 + 图标砖（染色 SF Symbol，不用 Apple/第三方 logo：商标问题）+ 名称 + 一行 tertiary caption（`BiRefNet_lite · MIT · 83 MB`；Vision 无 caption）+ 一句题材描述 + 行尾 Download/Delete。**隐私声明全窗只有一句**（2026-07-28 审计）：Models 节脚的盾牌行与 History 说明里的 "and never uploaded" 一并删除，只留窗底"照片不离开这台 Mac"那句——同一承诺说三遍读起来是免责声明。History 说明压成一句人话，不出现 "Application Support"。
- **引擎的说法（2026-07-28 晚定稿，同日验收后修订）**：模型名对用户零信息量，两个 BiRefNet 又是**题材分工不是质量梯度**（研究 A.6），所以行首是人话标签（Apple Vision / **Clean Cut** / **Fine Edges**）+ 一句题材描述，`BiRefNet_lite`·license·体积降为行下一行 tertiary caption（原为 chips，2026-07-28 审计收敛）；Vision 也占一行（它没有下载控件，但它是用户已有的那个选择）。**任何绝对耗时都不写**——"~1–2 s" 是在一台机器上量出来的，写进 UI 就成了对所有机器的承诺；Vision 说 "Instant"，模型不单独说速度（题材描述已经给了选择依据）。人话映射住在 app 层（`EngineLabels`），PluckKit 不掺用户文案，CLI 的 `--model <id>` 不变。
- **多语言与排版弹性（2026-07-28 审计）**：~~不做 app 内语言切换器——多语言走系统的"按 app 设定语言"，这是 mac 惯例也是 String Catalog 的机制；app 内再放一个是把系统已有的选择复制一份。~~ **同日推翻，见下条**。地基是排版：所有会换行的文案 `fixedSize(horizontal: false, vertical: true)`、按钮一律不定宽、窄面板（shelf 340pt）里的标签用 `layoutPriority` 先于控件让位、主窗口 Export 按钮宽度随文案走。验收方式是伪本地化——把 catalog 里所有英文串加长 30% 打一个包实跑，Settings / shelf / 主窗口三处均无截断（Settings 窗高自 589 → 617 自适应）。
- **app 内语言切换（2026-07-28 定案，推翻上一条）**：Settings 顶部一行 `Language`（`System / English / 简体中文`），存进 `Preferences.languageID`，默认 `system`。**免重启实时生效**：`L.s` 路由到一个可观察的当前语言 bundle（`Language` 单例 + `L.Route`，`Bundle(path:)` 指向 `<id>.lproj`），SwiftUI 的 body 调 `L.s` 即自动订阅；AppKit 那些"建一次就留着"的表面（`NSApp.mainMenu`、各 `NSWindow.title`、状态项无障碍标签、Settings/About 的窗口高度）挂 `.pluckLanguageDidChange` 通知重建。选项文字用各自的语言写（`English` 永远是 English，`简体中文` 永远是简体中文，两者 `Text(verbatim:)` 不进 catalog），只有 `System` 跟随当前语言。**术语基准**：cutout=抠图、Clean Cut=利落边、Fine Edges=柔细边、Drop or paste=拖入或粘贴、shelf 的 Recent=最近、Copy/Save 用 macOS 中文的拷贝/存储。翻译完整性有测试兜底（每个 en key 必须有 zh-Hans 值），新 key 漏翻会红。

- **预览面板的 Re-pluck 菜单（2026-07-28 晚）**：工具胶囊里第三个控件，列出**这张图还没走过的**引擎（未安装的显示体积，点了先下载）。结果作为新条目**并列插入**、面板切过去，旧条目原样保留——两种边缘是两个答案，覆盖会让对比要付一次重抠。结果的出身标注在主窗口行副标题与预览 Cutout 角标（非 Vision 才标）。

### 4.8 模型下载：托管、清单与校验

"不自己托管"的实际诉求是**不运维服务器**，而非让用户手动找文件——BiRefNet_lite 官方只有 PyTorch 权重，没有现成 mlpackage，用户自己下载原始权重也无法使用，转换产物必须由我们分发：

- **托管**：转换后的 `.mlpackage`（zip）作为 **Pluck 自己的 GitHub Releases 资产**发布（免费、无服务器、带宽由 GitHub 承担；MIT license 允许再分发，随包附原始 LICENSE 与来源声明）。
- **地址正确性 = 信任链**：`models/manifest.json` **打包在签名的 app bundle 内**（不从网络拉取），每条记录含 pinned URL（指向具体 release tag 的资产）+ SHA256 + 字节数 + license + 来源。链条：Developer ID 签名保证 manifest 未被篡改 → manifest 钉死 URL 和哈希 → 下载后校验 SHA256，不匹配即删除报错。URL 即使被劫持/替换，哈希校验也会拒绝。
- **下载器**（PluckKit `ModelRegistry`）：URLSession 下载到临时目录 → SHA256 校验 → 原子移动到 `~/Library/Application Support/Pluck/Models/<id>/`；支持断点续传与重试；加载模型前可再校验一次。CLI `pluck models pull` 走同一实现。
- **manifest 更新**：随 app 版本走（Sparkle 更新带来新 manifest），不做独立的远程 manifest——避免引入需要额外签名机制的第二信任通道，也符合"默认零网络"。

## 5. 里程碑

里程碑、当前状态与风险已移至 [roadmap.md](roadmap.md)（进度类信息的唯一真相源）。
