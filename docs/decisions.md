# 决策记录（追加式）

格式：日期 / 决策 / 背景与选项 / 理由。新决策追加在文件末尾。

## 2026-07-27 — 技术路线：Vision API 默认 + 可选 Core ML 模型

- **决策**：默认引擎用 `VNGenerateForegroundInstanceMaskRequest`（macOS 14+），高质量模型（BiRefNet_lite / InSPyReNet，均 MIT）按需下载，不打包进 app。
- **排除**：RMBG-1.4/2.0（BRIA）——CC BY-NC / OpenRAIL 条款对开源分发有法律风险。
- **理由**：体积是硬指标（不能"小 app 捆几个 G 模型"）；Vision 与系统「移除背景」同源，质量有保障；license 干净。详见 [research.md](research.md)。

## 2026-07-27 — 产品名：Pluck

- **决策**：产品名 Pluck，CLI 命令 `pluck`。
- **排除**：Peel/Peeler、Cutout、ClearCut（撞名）、Kirigami（KDE 框架）、PaperCut（打印软件）。
- **理由**：动词即用法（"pluck the subject out"），短、好记，CLI 观感自然。发布前做商标复查。

## 2026-07-27 — 分发：GitHub + Homebrew，不上 App Store

- **决策**：Developer ID 签名 + notarization，GitHub Releases（DMG + CLI 二进制）+ 自有 Homebrew tap，Sparkle 自动更新。
- **理由**：CLI、Sparkle、模型旁加载在 MAS 沙盒下均受限；Rectangle/Ice 已验证此通路。已有开发者账号可用于签名。

## 2026-07-27 — 仓库形态：Swift Package 单仓，PluckKit 唯一引擎

- **决策**：单仓，PluckKit（核心库）+ PluckCLI + PluckApp + Finder 扩展，全部依赖 PluckKit。
- **理由**：三入口行为一致；第三方可直接依赖 PluckKit；agent 协作时职责边界清晰。

## 2026-07-27 — 视觉方向：Liquid Glass 分级，参数跟随系统

- **决策**：采用 macOS 26 Liquid Glass 语言，内容/功能分层（抠图结果不加玻璃，chrome 用玻璃）；玻璃浓度分级——主窗口用标准窗口材质，popover/浮层用强玻璃；圆角、阴影等参数走系统默认（`containerConcentric` 等），不写死数值；珊瑚橙强调色每屏至多一处。菜单栏图标用"实心 blob + 虚线剪影"。
- **排除**：第一轮"暖奶油底 + 大面积珊瑚橙 + 自绘控件"方案（判定为 Web 风、与原生质感脱节）；羽毛图标（既有心智是"写作"，双关需注释才成立）。
- **理由**：mockup 里"窗口背后永远是壁纸"是理想化假设，真实桌面上大面积高透明会失控，故分级；Liquid Glass 本身仍在调整期（macOS 27 将改圆角），跟随系统可免费获得后续修正。调研依据见 [research.md](research.md) §五。定稿细节见 [product-plan.md](product-plan.md) §4.7。

## 2026-07-27 — 模型分发：GitHub Releases 托管转换产物，bundle 内 manifest + SHA256 信任链

- **决策**：BiRefNet_lite 等扩展模型由我们转换为 Core ML 后作为 Pluck GitHub Releases 资产分发；`models/manifest.json` 打包在签名 app bundle 内，含 pinned URL + SHA256 + license；下载后强制校验哈希，失败即删。manifest 只随 app 版本更新，不做远程 manifest。
- **排除**：让用户自行下载原始权重（官方无 mlpackage，下了也用不了）；独立远程 manifest（引入第二信任通道，需额外签名机制，违背零网络默认）。
- **理由**："不托管"的真实诉求是不运维服务器，GitHub Releases 满足；信任链锚定在 Developer ID 签名上，URL 被劫持也过不了哈希校验。详见 [product-plan.md](product-plan.md) §4.8。

## 2026-07-27 — 移除全局快捷键，剪贴板入口改为 popover 内 ⌘V

- **决策**：删除 ⌥⌘B 全局快捷键（Carbon 注册整体移除）。剪贴板流程改为：点菜单栏图标 → popover 内 ⌘V → 抠图 → **结果自动写回剪贴板** → 到目标 app ⌘V。SIGUSR1 触发器保留（headless QA + 脚本钩子）。
- **背景**：v0.1 实测反馈（用户）：全局快捷键记忆负担大、不直觉；popover 粘贴更符合"看着界面操作"的心智。
- **理由**：全局热键还有冲突与"装完即被占用一个组合键"的打扰成本；自动写回剪贴板保住了"不落盘闭环"（卖点 3），交互步数不变。

## 2026-07-27 — 菜单栏面板：NSPopover 换成非激活 NSPanel（shelf）

- **决策**：菜单栏点开的面板从 `NSPopover(.transient)` 换成自绘的非激活 `NSPanel`（`.nonactivatingPanel`/`.borderless`，`level = .popUpMenu`，`hidesOnDeactivate = false`，圆角与材质自绘）。关闭条件收敛为显式动作：再点状态项、Esc、⌘W、Quit。**不再有"点外面自动关"**。
- **背景**：v0.1 实测（用户）：面板开着时去 Finder 拖图，面板就被关掉了——`.transient` 的定义就是"与面板外的任何东西交互即关闭"，而"去别的 app 拿文件"必然是面板外交互。于是"整块 popover 都是拖放目标"这条改动在真实操作里根本用不上，拖放实际只剩菜单栏图标一个落点。
- **排除**：`.semitransient`（语义仍绑定窗口交互，且对状态项 popover 行为不确定）；`.applicationDefined` + 全局鼠标监听补关闭（用户点 Finder 起拖的那一下就是 mouseDown，照样会被判成"点外面"）。
- **理由**：这是 shelf 类工具（Dropover / Yoink / Ice）的通行形态，跨 app 拖拽是它们的主场景，NSPopover 的生命周期模型与之直接冲突。副作用是好的：容器由我们自绘后，圆角、材质、内边距才能真正对齐原型（见下一条）；⌘V 仍可用，因为面板由点击打开时主动 `makeKey`。代价是失去"点外面即关"的直觉，用显式关闭换拖放可用性。
- **修订（同日，见下方"拖放入口收敛"一条）**：NSPanel 保留，但"不做点外面自动关"这半条被推翻——拖放入口收敛到图标后，面板不再需要扛跨 app 拖拽。

## 2026-07-27 — 拖放入口收敛到菜单栏图标，面板恢复"点外面即关"

- **决策**：拖放的**唯一主路径是拖到菜单栏图标**：拖入时图标变为实心 + 珊瑚色（表示可接），松手即处理并**自动弹出面板**，用户在面板里看到占位卡→结果。面板本身仍接受拖放，但不再是承重路径。面板关闭恢复成"点任何外部区域即关"（全局 + 本地两个 mouseDown 监听；鼠标事件不需要辅助功能权限）。点图标只负责**打开**，不做 toggle——同一次点击已被 dismiss 监听处理过，再 toggle 会自己打自己。
- **背景**：上一条"不做自动关"是为了让面板扛住"去 Finder 拿文件"这段跨 app 拖拽。用户实测后给的方向是反过来的：不要让面板常驻，拖图标就够了。
- **理由**：拖到图标本来就是菜单栏工具的第一直觉，而且它比"先点开面板再拖进去"少一步。承重路径一旦不在面板上，面板就可以恢复符合系统直觉的即时消失，不必用"显式关闭"这种反直觉换来的可用性。

## 2026-07-27 — 面板圆角：`maskImage` 而非 `layer.cornerRadius`

- **决策**：无边框面板的圆角由 `NSVisualEffectView.maskImage`（带 `capInsets` 的可拉伸圆角图）实现，不用 `layer.cornerRadius + masksToBounds`；圆角形状统一用**正圆角**而非 `.continuous`，因为遮罩是手画路径、SwiftUI 侧的珊瑚描边是 `RoundedRectangle`，两者形状必须一致否则描边被切。
- **背景**：初版四角出现白色方块（用户截图）。
- **理由**：`blendingMode = .behindWindow` 的模糊由窗口服务器在图层树之外合成，`cornerRadius` 完全够不到它，`maskImage` 是唯一能作用于它的接口。

## 2026-07-27 — 原型视觉语言的实现映射（内容满铺 + 浮层玻璃工具条）

- **决策**：把 p3/p4 原型的视觉语言固化成四条可执行规则，App 内所有面板一律遵守：①**内容满铺到容器边缘**，不留 letterbox 灰底；②**工具条浮在内容之上**用玻璃材质，不用 `Divider()` 分隔区块；③**一级操作是无文字的圆形玻璃图标按钮**（Copy/Save/···），文字按钮只用于次要动作；④**不使用系统标题栏**，标题以玻璃胶囊叠在内容左上角。预览面板尺寸**跟随图片长宽比**（长边上限 560pt、短边下限 320pt），使图像能真正满铺。
- **背景**：第一版预览面板用了系统 titled 窗口 + 灰底 letterbox + `Divider()` + 默认按钮，与原型是两种语言（用户实测反馈）。
- **理由**：原型的"爽感"来源就是图像占满视野、chrome 退到图像之上。规则写成条款而不是逐屏描述，是为了后续浮层/主窗口复用同一套判断，避免每屏重新讨论。

## 2026-07-27 — 处理中反馈：网格占位卡 + 图标脉冲，不用全局进度条

- **决策**：处理中状态有两处表达。①**面板内**：Recent 网格头部插入占位卡，内容是输入图的缩略图（去饱和 + 压暗）+ 循环扫光，超过 250ms 才叠加小号圆形 spinner；完成时**原地交叉淡出**换成结果卡；失败时占位卡闪红边后淡出。②**菜单栏图标**：处理中做 1.2s 循环的呼吸脉冲，取代当前的恒定半透明。
- **排除**：面板顶部横向进度条（批量时不知道在处理哪张）；纯 spinner 占位（短任务下闪一下比不闪更烦）。
- **理由**：占位卡在原位置显示"正在处理的是哪一张"，批量拖入时尤其必要；用输入图本身当占位而非空 spinner，使 <250ms 的快任务看起来是瞬时替换而不是闪烁。图标脉冲是面板关闭时（拖到图标上）唯一的进度表达。

## 2026-07-27 — Recent 去重要可见：命中已有条目时高亮而非静默

- **决策**：`RecentStore` 按抠图字节去重的行为保留，但命中已有条目时必须给出可见反馈——把该条目提升到首位并让它**闪一次高亮边框**。同时面板提供 **Clear** 按钮清空 Recent。
- **背景**：把 Recent 里的 cutout 拖出去再拖回面板，产物字节与已有条目完全相同，走了静默提升分支——用户看到的是"这张图处理不了"（用户实测反馈）。
- **理由**：去重本身是对的（不该让同一张图刷屏网格），错的是它没有任何外化表现。反馈成本极低，且顺带解决"我刚才那张跑哪去了"这类一般疑惑。

## 2026-07-27 — 浮层层级显式声明：预览面板高于 shelf

- **决策**：两个浮层的 `NSWindow.Level` 写在一处并显式排序——shelf = `.popUpMenu`，预览面板 = `.popUpMenu + 1`。规则推广为 §4.7 第 ⑤ 条：从某面板打开的面板必须叠在它上面。
- **背景**：shelf 为了浮在普通窗口之上设了 `.popUpMenu`，预览面板沿用默认 `.normal`，于是点 Recent 缩略图打开的预览被 shelf 挡住（用户截图）。
- **理由**：两个浮层都不是普通窗口，谁在上不能靠默认值。常量放同一个 `extension` 里，是为了让"顺序"本身在代码里可读，而不是散落在两个文件里靠 rawValue 心算。
- **补记（同日）**：第一版设了 `level` 但没生效——`NSPanel.isFloatingPanel` 的 setter 会**写 `level`**（false → `.normal`），而那行恰好在 `level` 赋值之后，把它静默抹掉了。现在不碰 `isFloatingPanel`，并在代码里注明这个陷阱。

## 2026-07-27 — 预览面板贴着 shelf 摆，不与之重叠

- **决策**：预览面板开在 shelf **旁边**（留空隙的一侧取剩余空间较大者，顶边对齐，间距 10pt），而不是屏幕居中压在 shelf 上；shelf 关闭时才居中。几何逻辑拆成不依赖 `NSScreen` 的静态函数并加测试（副屏、窄屏、超高图这些本机屏幕上碰不到的情况）。
- **背景**：修好层级后，两块玻璃面板仍然叠在一起，观感是杂乱（用户反馈"让预览窗口默认不和 popover 重叠，离它稍微远一点，但不能太远"）。
- **理由**：预览是**从** shelf 里点开的，盖住 shelf 就等于挡住下一次点击的落点。层级与摆位是互补而非二选一：正常情况下靠摆位互不遮挡，屏幕窄到两块放不下时靠层级保证预览在上。

## 2026-07-27 — 占位卡与结果卡共用同一身份，网格合成单一列表

- **决策**：`finish` 用占位卡的 ticket UUID 作为 `RecentItem.id`（不再新生成）；`ShelfView` 把 `pendingItems + recents.items` 合成一个 `ShelfCell` 列表，用**单个 `ForEach`** 渲染。
- **背景**：占位卡完成时肉眼可见"位置变了"（用户实测）。原因是两个并列 `ForEach` 跨两个数组、两套 UUID：完成 = 从 A 删除 + 向 B 插入，SwiftUI 没有理由认为这是同一个格子，只能把它当成一次删除加一次无关插入来动画。
- **理由**："原地交叉淡出"（见上方处理中反馈一条）不是动画参数问题，是身份问题——身份跨越状态迁移存活，SwiftUI 才会把它当成同一格的内容变化。身份继承由测试锁定（`testResultInheritsThePlaceholderIdentity`），否则以后有人随手改回 `UUID()` 不会有任何报错。

## 2026-07-27 — 无边框面板的拖动：顶部 44pt 条带作为标题栏

- **决策**：预览面板顶部 44pt（宽度止于关闭按钮前 44pt）是窗口拖动区，由一个 `mouseDownCanMoveWindow` 返回 true 的 `NSView`（`WindowDragHandle`）实现；标题胶囊设 `allowsHitTesting(false)`，让点击落到下面的条带上。图片区域仍然整块归 before/after 擦除手势。
- **排除**：`isMovableByWindowBackground`（图片区被 SwiftUI 的 `DragGesture` 全部吃掉，等于没有可拖区）；把擦除限制到滑块把手上换取整图可拖（牺牲的是这个面板存在的理由）；`WindowDragGesture`（macOS 15，部署目标是 14）。
- **背景**：§4.7 规则 ④ 拿掉了系统标题栏，但没有把标题栏**能拖**这件事还回来（用户实测：预览窗口不能拖拽移动）。
- **补记（同日）**：只重写 `mouseDownCanMoveWindow` 不够——AppKit 是在 `hitTest` 返回的那个 view 上问这个问题，而 SwiftUI 会把 representable 再包一层它自己的宿主 view，那一层的答案是默认值（否，除非窗口 movable by background，而我们刻意不开）。改为同时重写 `mouseDown` 调 `window?.performDrag(with:)`：两条路径任一走通即可。
- **同批**：关闭按钮改为**常驻显示**，不再 hover 才出现。无边框窗口没有别的可见出口，Esc 能用但屏幕上没有任何东西这么说；而"指针已经移到正确位置才现身"的控件教不会任何人那个位置在哪。
- **理由**：自绘 chrome 要连同它的行为一起自绘。条带避开关闭按钮是因为拖动区与控件重叠时谁接到 mouseDown 是掷硬币，输的一方是一个画得出来、亮得起来、但永远不触发的按钮；这条几何约束有测试（`PreviewDragRegionTests`，断言的是区域 frame 而非 hit-test——`NSHostingView.hitTest` 需要真实窗口才会去查 SwiftUI 自己的命中树）。

## 2026-07-27 — 端到端管线下沉 PluckKit：`PluckPipeline` + `Thumbnail`

- **决策**：新增 `PluckPipeline.run(_:) -> PluckRun`（load → mask → compose 一次调用）与 `PluckSource`（file/data/image）；`PluckRun` 同时保留 `input`（已应用 EXIF 方向）、`mask`、`image` 三者。CLI `Runner` 与 App `PluckService` 改为纯薄壳。缩略图按**长边**降采样的 helper 公开为 `Thumbnail`。
- **背景**：同一段管线在 CLI Runner 和 App PluckService 各写了一遍，Finder 扩展会是第三遍（roadmap 技术债首项）。两份拷贝已经开始漂移：App 那份直接调 `Compositor.cutout`，`--background` 这条路在 App 侧根本不存在；App 还自己重写了一份 CGContext 降采样。
- **`PluckRun` 保留中间态而非只返回结果图**：CLI 只要 `image`，但 App 的 before/after 擦除需要 `input`，将来的"修边"UI 需要 `mask`；任一项少给，调用方就得重新解码或重新抠一次。
- **只公开 `Thumbnail`，不公开 `ImageBuffers`**：需要外露的是"按长边缩到 320pt"这个需求，不是 RGBA/Gray 两套规范化缓冲布局。把布局导出去等于此后每次改它都是 breaking change，而库外没有人受益。`ImageBuffers.downsampled(_:maxPixels:)` 仍是内部的、面向引擎输入上限的那一个——两者服务不同的问题，不合并。
- **stdin 仍在 CLI 读**：抽干 stdin 是一次性副作用，交给可重试的管线内部去做，失败重试会静默产出空图。

## 2026-07-27 — 不建 Xcode 工程，用 `Scripts/bundle.sh` 组 .app

- **决策**：v0.1/v0.2 前半段不引入 `.xcodeproj`。`Scripts/bundle.sh` 把 SwiftPM 产物组装成 `Pluck.app`：Info.plist（模板在 `Packaging/`）、xcstringstool 编译 String Catalog、`Scripts/make-icon.swift` 画 icns、ad-hoc 签名并 verify。Bundle ID `com.pluckapp.Pluck`（见同日下一条）。
- **背景**：roadmap 原计划"v0.2 建 Xcode app 壳"来解决 String Catalog 不编译。但被卡住的实际只有两件事——`.xcstrings` 原样 copy 从不编译、没有 .app bundle——两件都是命令行能干的，`xcstringstool` 就在 Xcode 里。
- **理由**：签名与公证不需要工程文件（`codesign` / `notarytool` 直接作用于 .app），所以引入 `.xcodeproj` 只会换来 `swift test` / `xcodebuild test` 双轨和一个天生冲突的二进制式工程文件。Xcode 工程真正不可替代的时刻是 **Finder Quick Action**（`.appex` 嵌套签名），到那时再建，且到那时它要解决的是一个真问题而不是一个想象中的问题。
- **顺带修掉的坑**：`Bundle.module` 的 SwiftPM 生成访问器找的是 `Pluck.app/Pluck_PluckApp.bundle`（在 `Contents/` 之外，codesign 不接受），且两个候选都不存在时直接 `fatalError`——打包后的 app 一旦碰它就是启动崩溃。`L.catalog` 改为探测 `Contents/Resources/en.lproj` 决定用 `Bundle.main` 还是 `.module`，打包分支永不求值 `.module`。
- **验证**：临时给 `Clear` 加一条 `zh-Hans` 译文重打包，`zh-Hans.lproj` 正确生成且运行时取到"清空"，随后还原。多语言这条链路从此是通的，不是"应该通的"。

## 2026-07-27 — Bundle ID 定为 `com.pluckapp.Pluck`

- **决策**：`com.pluckapp.Pluck`。Finder 扩展将来用 `com.pluckapp.Pluck.FinderQuickAction`。
- **排除**：`com.ruochenlyu.pluck`（把个人名字焊进一个开源项目的标识符，日后换维护者或加协作者都尴尬）；`com.github.<user>.pluck`（github.com 不是我们的域名，这恰是反向 DNS 约定要避免的事）；`org.pluck.Pluck`（`pluck` 是常见词，裸占顶级项目名撞车概率高）。
- **理由**：反向 DNS 约定要求命名空间对应一个**项目自己**的域名。roadmap v1.0 本就要做官网，`pluckapp.com` 是那个域名的自然候选——**发布前应确认能拿到**；拿不到就换成实际注册下来的那个（此刻改的成本是零，发布后是永久）。
- **不需要在 Developer 后台注册 Identifier**：Developer ID 分发且不使用任何 capability 的 app 无此要求。等 Finder 扩展需要 App Group 时才需要。

## 2026-07-27 — Bundle ID 改定为 `me.kshift.Pluck`（推翻上一条）

- **决策**：`me.kshift.Pluck`（`kshift.me` 的反向 DNS）。Finder 扩展将来用 `me.kshift.Pluck.FinderQuickAction`。上一条的 `com.pluckapp.Pluck` 作废。
- **背景**：上一条把 `pluckapp.com` 当成"发布前去注册"的前提。维护者的决定是不为这个 app 单独注册域名，用现有域名的二级域（`pluck.kshift.me`）。反向 DNS 约定要的就是这个——命名空间对应一个**确实控制**的域名，而不是一个漂亮但还没买下来的域名。
- **在 `kshift.me` 与 `aix4u.com` 之间选前者**：`aix4u.com` 是 AI 品牌的命名空间，而 Pluck 的核心承诺恰恰是"离线、不上网、照片不离开这台 Mac"。bundle id 会出现在 `codesign -dv`、Console 日志、崩溃报告里，被人读到的时候不该暗示这是个 AI 服务的客户端。
- **成本**：此刻改动等于改一行 plist（`bundle.sh` 早已从 plist 反读 id）。发布之后再改就是换一个 app——用户偏好、TCC 授权、Sparkle 更新链路全部重置。这也是为什么这条决策必须在第一次签名分发之前落定。

## 2026-07-27 — Bundle ID 终定为 `com.aix4u.pluck`

- **决策**：`com.aix4u.pluck`（`aix4u.com` 的反向 DNS）。Finder 扩展将来用 `com.aix4u.pluck.FinderQuickAction`。同日前两条（`com.pluckapp.Pluck`、`me.kshift.Pluck`）均作废，本条为准。
- **理由**：维护者在自己控制的两个域名之间选定 `aix4u.com`。上一条选 `kshift.me` 的理由（避免 AI 品牌命名空间与"离线"承诺相冲）是一个措辞层面的顾虑，不是工程约束——bundle id 不出现在任何面向用户的界面里，`.com` 也比 `.me` 更长命。域名的归属是维护者的决定，采纳。
- **一天三条同题 ADR 的教训**：命名空间取决于"哪个域名归我们"，这是个事实问题而非设计问题，应当在写第一行 plist 之前问清楚，而不是先按约定推演出一个漂亮答案再逐条推翻。所幸 `bundle.sh` 从 plist 反读 id，三次改动各是一行。

## 2026-07-27 — 菜单栏图标够不着时，shelf 自己找地方落下

- **决策**：`AppDelegate.statusAnchor()` 判定状态项是否**真的够得着**；够不着（返回 nil）时 shelf 从可用区顶部中央落下，而不是挂在一个不存在的图标下。判 nil 的三种情形：拿不到 button/window、按钮宽度 ≤ 1pt、以及矩形与 `NSScreen.auxiliaryTopLeftArea/auxiliaryTopRightArea` 都不相交（这两块是刘海**没占住**的那段菜单栏，都不沾即在刘海底下）。
- **另外两条逃生通道**：`applicationShouldHandleReopen` —— 重复启动已在运行的 app，LaunchServices 发的是这个而不是起第二份，对一个没有 Dock 图标的 app 来说，这是用户唯一做得出来、我们又一定收得到的手势；以及启动 700ms 后若仍不可达就自动开一次 shelf（状态项要等菜单栏布完版才落位，所以不能立刻问）。
- **背景**：`LSUIElement` app 无 Dock 图标、无窗口，状态项被刘海或第三方菜单栏管理器（Ice/Bartender）收起来时，屏幕上就再没有任何一个可点的东西——2026-07-27 实测发生，并且直接挡住了我自己的 UI 验收。这条债本来排在 v0.2，被提前是因为它不是体验问题而是可用性归零。
- **顶部中央而非记住上次位置**：把图标藏起来的那个东西（刘海、满员的菜单栏、管理器）恰恰只可能占住菜单栏那一行，顶部中央是它够不到的地方；而"上次位置"在第一次就没有值。
- **安置逻辑改为纯静态函数** `ShelfPanelController.origin(for:under:in:)`：值得测的正好是本机没有的那些屏幕（刘海机、副屏、比 shelf 还小的外接屏），只有不碰 `NSScreen` 才测得了。无 anchor 分支用 `margin` 而不是 `gap` —— 没有图标可挂，`visible.maxY` 本来就在菜单栏之下，那就是一条普通的边距。

## 2026-07-27 — 去重改在进引擎之前判，而不是拿结果去比

- **决策**：处理前先算**输入字节**的 SHA256，命中 `RecentStore` 里任一条目的指纹就直接提升+高亮那一条，不再跑引擎（`PluckOutcome.superseded`）。原先"结果入库时按输出指纹去重"保留不变，两者互补。
- **背景（QA 实测）**：抠图成功后结果会写回剪贴板，所以连按两次 ⌘V，第二次抠的是第一次的**输出**。而抠图对自身输出并不幂等——同一张图连过三遍，三个不同的 SHA256（每过一遍边缘 alpha 再被削一点）。于是输出指纹永远对不上，格子里堆出一串几乎一样、却一次比一次糟的副本。原有的去重测试用 mock 返回固定字节，正好绕开了这件事，所以它一直是绿的。
- **为什么必须在处理**前**判**：`ClipboardPlucker.run` 在返回前就把结果写回剪贴板了。等拿到结果再丢弃，用户的剪贴板已经被那份更糟的版本覆盖掉了。因此 `onInput` 回调改为返回 `Bool`——它是唯一还来得及拒绝这次任务的位置。
- **顺带覆盖了用户最初报的那条**："把抠好的图拖回来没反应"——存盘后的 cutout 文件字节就是我们写出去的那份，同一条指纹、同一条路径。`DroppedPayload.bytes` 对 `.file` 重新读盘而不是交回解码后再编码的东西，否则哈希的不是同一个东西。
- **测试**：`MockPasteboard.writePNG` 现在会回填 `stored`，即模拟真实剪贴板的写-读闭环——不这么做，测试永远看不到"上一次的结果就躺在下一次的输入位置上"这个局面。新增断言直接数引擎被调用的次数，而不只是数格子。

## 2026-07-27 — 用户挪过的预览面板位置，记到 session 结束

- **决策**：`PreviewPanelController` 记住两个点：`placedOrigin`（我们上次把面板放在哪）和 `userTopLeft`（用户后来把它拖到哪）。每次 `show` 之前先比一次——frame 的 origin 和我们放的位置对不上，只可能是被拖过；一旦有了 `userTopLeft`，之后每次打开都按它落位，不再贴回 shelf 旁边。
- **背景**：面板是"一个面板复用"，点第二张缩略图是换内容而不是开新窗。副作用是每次 `show` 都会重新摆位，于是用户把它拖到顺手的地方之后，下一次点击又把它扔回 shelf 边上——把一个明确的用户操作当成没发生过。
- **记左上角而不是 AppKit 的 origin**：面板按图片比例逐张 resize，`setContentSize` 是从左下往上长的。记住下边缘的话，点过一张长图之后面板的顶边就会跳到别处；而眼睛盯着的恰恰是顶边。
- **仍然 clamp**：记住的位置照样过 `clamp`，因为外接屏会被拔掉、分辨率会变——一个记在已经不存在的屏幕上的坐标必须让位给现在这块。
- **不持久化到磁盘**：只活到进程结束。窗口位置属于 v0.2 那条"历史记录持久化"要一起解决的偏好存储问题，为它单开一个 UserDefaults key 是在正式方案之前先埋一个要迁移的东西。
- **`origin(for:keeping:in:)` 同样是纯静态函数**，和 `origin(for:beside:in:)` 并列，理由一样：值得测的是 resize 之后顶边有没有动、以及记住的位置跑到屏幕外之后会不会被拉回来。

## 2026-07-27 — 齿轮按钮改成 About，而不是造一个 Settings 窗口

- **决策**：shelf 底栏那颗 `gearshape`／`L.s("Settings")` 改为 `info.circle`／`L.s("About Pluck")`。行为一直就是 `orderFrontStandardAboutPanel`，改的是标签而不是行为。
- **理由**：product-plan.md §设置 定义的四项——默认引擎、模型管理、输出格式、快捷键——在 v0.1 一项都不存在（引擎固定 Vision、输出固定 PNG、全局快捷键已明确移除、模型是 v0.3）。所以摆在这里的齿轮是一个说谎的控件：它承诺了一个 app 还没有的界面。
- **不为了让齿轮名副其实而临时发明设置项**（例如开机自启）：那是拿"控件已经画在那儿了"倒推功能范围。开机自启记进 roadmap 当 v0.2 候选，等有第二项、第三项设置时一起做一个真的 Settings。
