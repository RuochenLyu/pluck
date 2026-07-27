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
3. **原生体验**——菜单栏拖拽、Finder 右键、popover 里 ⌘V 即抠即回剪贴板（不落盘闭环）、批量拖入带进度。
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
│   └── PluckApp/            # SwiftUI app
│       ├── MenuBar/         # 菜单栏常驻 + 拖放目标
│       ├── MainWindow/      # 批量队列、对比预览、导出
│       └── ResultOverlay/   # CleanShot X 式处理完浮层
├── Extensions/
│   └── FinderQuickAction/   # Action Extension（右键「Pluck 移除背景」）
├── skills/
│   └── pluck/SKILL.md       # agent skill，随仓库分发
├── models/manifest.json     # 可下载模型清单（名称/URL/SHA256/license/体积）
└── homebrew/                # cask (app) + formula (cli)
```

核心设计：**PluckKit 是唯一引擎，App、CLI、Finder 扩展都是它的薄壳。** 保证三个入口行为一致，也让第三方能直接依赖 PluckKit。

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

- **菜单栏常驻**：**拖到图标是拖放的主路径**——拖入时图标变实心 + 珊瑚色，松手即处理并自动弹出面板。点击图标也可打开面板（只打开，不 toggle）。面板是自绘的非激活 NSPanel（不是 NSPopover，容器视觉要自己控），内含 Recent 网格 + Clear，本身也接受拖放但不是承重路径；点面板外任何地方即关，Esc / ⌘W 同。剪贴板流程：面板内 ⌘V → 抠图 → 结果自动写回剪贴板 → 目标 app ⌘V，**中间不落盘**（2026-07-27 起废弃全局快捷键方案）。点击 Recent 项打开预览面板：before/after 拖拽滑块 + Copy/Save。
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
pluck photo.jpg --json                 # 机器可读：输出路径/尺寸/耗时/是否检测到主体
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

定稿图见 [prototypes/](prototypes/)（p1–p6），提示词底稿见 [prototypes/prompts.md](prototypes/prompts.md)。要点：

- **视觉语言**：macOS 26 Liquid Glass，内容/功能分层——抠图结果与棋盘格是内容层不加玻璃；浮层容器、按钮、工具栏是功能层用玻璃。圆角/阴影参数跟随系统，不写死数值。
- **四条硬规则**（2026-07-27 补，从原型反推、App 内所有面板通用）：①内容满铺到容器边缘，禁止 letterbox 灰底；②工具条浮在内容之上用玻璃材质，不用 `Divider()` 分区；③一级操作是无文字圆形玻璃图标按钮，文字按钮只给次要动作；④不用系统标题栏，标题以玻璃胶囊叠在内容左上角。预览类面板尺寸跟随图片长宽比（长边 ≤560pt、短边 ≥320pt）。⑤**从某个面板打开的面板必须叠在它上面**——层级顺序显式声明（shelf = `.popUpMenu`，预览 = `.popUpMenu + 1`），不靠默认值碰运气。
- **玻璃分级**（mockup 的玻璃浓度是上限不是规格）：主窗口用标准窗口材质保可读性（背后可能是任意窗口而非壁纸）；菜单栏 popover 与结果浮层保持强玻璃。
- **强调色**：珊瑚橙每屏至多一个染色元素（主按钮/进度/选中勾），其余中性。
- **图标**：实心有机 blob + 虚线剪影（主体被拽走留下轮廓）；18px 菜单栏版虚线简化为 4–5 段粗 dash，进开发后直接画矢量模板 PDF。羽毛方案废弃。
- **入口层级**：菜单栏为主入口（单张高频场景），主窗口为批量处理场景（保留空状态）。
- **结果浮层**（产品灵魂，无竞品做到）：出现在松手位置附近，约 260×300，图像满铺无留白；一级操作仅 Copy/Save/···（换背景收进溢出菜单）；底边珊瑚细线做 5s 自动消失倒计时，悬停暂停，无文字标签；"Before" 按住看原图。
- **批量队列**：行内 hover 出 Copy/Save，整行可拖拽单个结果。
- **设置**：原生 toolbar tab 形态；引擎行用单色 SF Symbols，不用彩色徽标（Apple logo 有商标问题）。

### 4.8 模型下载：托管、清单与校验

"不自己托管"的实际诉求是**不运维服务器**，而非让用户手动找文件——BiRefNet_lite 官方只有 PyTorch 权重，没有现成 mlpackage，用户自己下载原始权重也无法使用，转换产物必须由我们分发：

- **托管**：转换后的 `.mlpackage`（zip）作为 **Pluck 自己的 GitHub Releases 资产**发布（免费、无服务器、带宽由 GitHub 承担；MIT license 允许再分发，随包附原始 LICENSE 与来源声明）。
- **地址正确性 = 信任链**：`models/manifest.json` **打包在签名的 app bundle 内**（不从网络拉取），每条记录含 pinned URL（指向具体 release tag 的资产）+ SHA256 + 字节数 + license + 来源。链条：Developer ID 签名保证 manifest 未被篡改 → manifest 钉死 URL 和哈希 → 下载后校验 SHA256，不匹配即删除报错。URL 即使被劫持/替换，哈希校验也会拒绝。
- **下载器**（PluckKit `ModelRegistry`）：URLSession 下载到临时目录 → SHA256 校验 → 原子移动到 `~/Library/Application Support/Pluck/Models/<id>/`；支持断点续传与重试；加载模型前可再校验一次。CLI `pluck models pull` 走同一实现。
- **manifest 更新**：随 app 版本走（Sparkle 更新带来新 manifest），不做独立的远程 manifest——避免引入需要额外签名机制的第二信任通道，也符合"默认零网络"。

## 5. 里程碑

里程碑、当前状态与风险已移至 [roadmap.md](roadmap.md)（进度类信息的唯一真相源）。
