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

## 2026-07-27 — 启动时清空 `<tmp>/Pluck/`

- **决策**：`applicationDidFinishLaunching` 的第一行（同步）删掉整个 `<tmp>/Pluck/`。这个目录只有 App 在用，PluckKit 和 CLI 都不碰。
- **背景**：每张抠好的图都会落一份 PNG 到 `<tmp>/Pluck/<uuid>/`，因为 `NSItemProvider(contentsOf:)` 要一个真文件才能把格子拖进别的 app。Clear 会连临时文件一起删，但**退出不会**——⌘Q 和崩溃都什么也不删。实测这台机器上躺着十几张历史 session 的 cutout。
- **为什么这是隐私问题而不是清洁问题**：这些是用户照片的明文副本，而这个 app 唯一的承诺就是"照片不离开这台 Mac"。"不离开"不该顺带意味着"堆在一个你不知道的目录里"。grid 是 session 作用域的，所以启动那一刻目录里的东西一定没人再指向它。
- **同步而不是 detached**：detached 的清扫可能落在第一次 drop 已经写完之后，把 grid 正指着的文件删掉。这一行的位置在任何输入通道装好之前，不存在竞争。
- **`discardOrphanedTemporaryFiles(at:)` 带默认参数**：测试指向自己的目录，否则跑一次测试就会把开发者正在跑的那份 app 的临时文件删掉。

## 2026-07-27 — 条目就是那个文件：cutout 落盘，内存只留缩略图

- **决策**：一条 recent 条目对应磁盘上一个以 id 命名的目录，里面三个文件——`<原图名>.png`（cutout）、`original.png`（降采样后的输入）、`thumbnail.png`。内存里的 `RecentItem` 只留 `thumbnailPNG` 的字节和另外两个 URL，cutout 与 original 在需要时（Copy/Save/预览滑块）现读。
- **背景**：原先一条条目在内存里是同一张图的三份副本，磁盘上还有第四份——那份只是为了 `NSItemProvider(contentsOf:)` 能拖出去。20 条约 60 MB 常驻，而且这恰恰是历史记录持久化做不了的原因：每次变更把这么多状态写回磁盘，不是能在 main actor 上做的事。反过来之后，拖出用的临时文件和历史文件合并成了同一份产物，持久化的代价降到一个小 `index.json`。
- **两个根，各有各的性格**：`<tmp>/Pluck/` **不写 index**——"不要记住"就该意味着字节随 session 一起死；`~/Library/Application Support/Pluck/History/` 写 index。启动时 `<tmp>/Pluck/` 一律清空，History 只在偏好关闭时清空。
- **index 说顺序，目录说存在，冲突时目录赢**：load 时 PNG 已不在的记录被丢掉，没有任何存活记录指向的目录被删掉。这就是"写完文件、还没写 index 就崩溃"这一窗口的自清理方式——不需要事务，因为目录本身就是真相。
- **写失败现在是任务失败**（`.notWritten`）。内存里不再有副本，所以一个 Copy/Save/预览/拖出全都静悄悄什么也不做的格子，比一句"检查磁盘空间"糟得多。
- **关掉历史是写一个空 index，不是删文件**：格子里已有的条目正靠这些文件活着。它们在下一次启动被扫掉（偏好为关时两个根都扫）。
- **`CutoutArchive.discard` 有一道护栏**：只删「父目录的父目录正好是两个已知根之一」的条目目录。手工构造的 URL、或者未来版本写下的 index，删不掉任何东西。

## 2026-07-27 — 有了三项真设置，于是有了 Settings 窗口（并把齿轮请回来）

- **决策**：新建 `SettingsWindowController`／`SettingsView`（`Form` + `.grouped`，标准系统标题栏），shelf 底栏在 ⓘ 旁边重新放上 `gearshape`。**这条推翻同日早些时候「齿轮改成 About」那条**——推翻的理由正是那条自己写的："等有第二项、第三项设置时一起做一个真的 Settings。"现在有三项：保留历史、开机自启、清空历史。
- **为什么它长得像系统窗口而不像 §4.7 的玻璃面板**：§4.7 那套无边框规则是给挂在菜单栏下、站在用户工作前面的面板定的。Settings 是用户主动去找、开一次、关掉的窗口，它应该和这台机器上别的 Settings 窗口长得一样。
- **一栏而非分页**：product-plan §设置 要的 tab 工具栏等 v0.3 模型面板到位再说；一页内容配一排 tab 是为了 chrome 而 chrome。
- **偏好存哪**：`UserDefaults`。预览面板位置存成两个 double 而不是归档的 `CGPoint`——一个 `defaults read` 读不出来的偏好是一个没人能调试的偏好。
- **开机自启用 `SMAppService.mainApp`，并且以「自己确实是个 .app」为前提**（`Bundle.main.bundleIdentifier != nil && bundleURL.pathExtension == "app"`）。裸 `swift build` 出来的可执行文件上调它，会注册一个指向 `.build` 目录的登录项。够不到时开关置灰并说明，而不是假装成功。
- **离线声明放进 Settings 最后一段**：不是自夸，是这个产品全部立足的那一条承诺，而怀疑它的用户第一个会去翻的地方就是设置。

## 2026-07-27 — `MattingEngine.mask` 去掉 `async`，并加一道并发闸

- **决策**：`MattingEngine.mask(for:)` 的签名从 `async throws` 改成 `throws`；`PluckPipeline.run` 改为在 `PluckQueue` 上跑整条同步链（decode → mask → compose）。`PluckQueue` 是一个 actor，同时干两件事：**限流**（默认宽度 `clamp(核心数/3, 2...4)`）和**换线程**（把同步工作 `async` 到自己的私有并发 `DispatchQueue`）。
- **背景**：Vision 的 `handler.perform` 是同步阻塞调用。把它包在 `async` 里不会让它变成非阻塞，只会**藏起它阻塞的是谁**——协作线程池，每张在飞的图占一条。这条债在 roadmap 里挂着"v0.2 批量队列动工前需决定"，而批量队列正是让它变成真问题的那件事：拖进一个 40 张的文件夹，就是 40 份全分辨率的输入+mask+合成缓冲同时在内存里（12 MP 约 48 MB 一份），也就是**让用户的选择决定 app 的内存上限**。
- **为什么两件事必须一起做**：只限流不换线程，`width` 条协作线程照样被同步工作停住（协作池的线程数就是核心数量级，很容易把它坐满）；只换线程不限流，内存照旧无界。
- **宽度取 2–4**：Vision 在 ANE 上本来就串行，再宽只是多占内存换不到吞吐；下限 2 是为了让一张大图不至于把整条队列卡死。
- **交接而非"释放再抢"**：`release()` 直接 resume 队首的 waiter，而不是把计数减一让所有人重新竞争——否则后到的任务可能插到排了很久的任务前面。
- **占位缩略图走另一条窄队列**（`PluckService.decoding`，宽度 2）：它们是"我收到这个文件了"的唯一回执，排在 40 个抠图后面就意味着 40 行空白等一分钟。

## 2026-07-27 — 主窗口：一列、按整张计数、不放格式选择

- **决策**：`MainWindowController` 建一个**标准系统标题栏**的可缩放窗口（p1/p2 画的就是标准标题栏），内容是一列 batch 行：44pt 棋盘缩略图 + 文件名 + 像素尺寸，hover 出 Copy/Save，整行可拖出，点击开预览面板。底栏是盾牌 + 离线声明 + `Export All…`。shelf 底栏加一颗 `macwindow` 作为入口。
- **不套 §4.7 的无边框玻璃**：理由同 Settings 那条——§4.7 是给菜单栏面板定的，而 §4.7 自己那句玻璃分级写的就是"主窗口用标准窗口材质"。为了满足一条关于浮动面板的规则去手绘红绿灯和缩放边角，是把设计的字面意思执行到它不再有意义的地方。
- **进度按整张图计数，没有每行百分比**：Vision 一次请求内部不报告任何进度，p2 那个"60%"拿不到。能给一个动画配一个数字，但那个数字会是假的。计数条只在 `total > 1` 时出现——单张时行内那颗 spinner 已经说完了全部。
- **失败和重复也计入 done**：三张里一张坏掉，进度条如果只数成功就会永远停在 2/3，读起来是"卡住了"。
- **不放 PNG / Transparent 两个下拉**：一个只有一个选项的选择器，和早上那颗"说谎的齿轮"是同一个错误。换背景色属于结果浮层那一栏，等它做出来再说。
- **一列，最新在上**：和 shelf 网格同一个顺序、同一批 id。p2 画的是按拖入顺序从上往下排——那在只有一次拖放时读得通，但历史持久化之后列表里混着上周的条目，"第一条"就不再有含义。
- **Export All 是选目录，不是静默写到记住的目录**：二十个文件出现在一个几个月前选过、现在得回想的地方，不叫方便。记住的是**选择器从哪里打开**，那才是真正烦人的部分。重名不覆盖，改追加 ` 2`、` 3`——两个文件夹各有一张 `IMG_0042.jpg` 是常态而不是奇例。
- **偏好里存的是路径不是 security-scoped bookmark**：Pluck 没有沙盒，bookmark 换不来任何东西，只换来一段没人读得懂的 blob。目录被删或宗卷被拔时读回 nil，而不是把面板送到一个已经不存在的地方。
- **⌘V / ⌘W 由 `AppDelegate` 的按键监视器分发**：accessory app 永远不显示菜单栏，`performClose(_:)` 的 ⌘W 是靠 File 菜单里那条菜单项发出去的，而这个 app 没有菜单。窗口有真标题栏，不等于它有真菜单。

## 2026-07-28 — 砍掉开机自启，也不做"抠完自动弹"的结果浮层

- **决策**：删除 `Preferences.launchesAtLogin` / `canLaunchAtLogin` / `loginItemError` 与 `SMAppService` 依赖，Settings 的 General 一节整节移除（现在是 History 一节 + 离线声明）。同时把 roadmap v0.2 里的"结果浮层"改为**不做自动弹出**，结果仍然由用户点开预览面板查看。**这条推翻 2026-07-27 那条 Settings ADR 里的开机自启项**。
- **为什么删自启**：这是维护者的判断——抠图是一件用户主动发起的事，不是一件需要有人常驻等待的事。留着开关等于替用户默认"它该常驻"，而这个开关本身的存在就是一种建议。少一项设置也少一项要跨版本兑现的承诺。
- **顺带删掉的技术债**：`SMAppService` 那套"我到底是不是个 .app"的探测、开关失败回滚、置灰加解释文案，连同它唯一那条测试一起消失。它们本来都是为了让一个开关诚实——最诚实的开关是没有这个开关。
- **为什么不做自动弹浮层**：CleanShot 那套"截完就飘一张出来"是给**截图**设计的，截图的下一步几乎总是立刻用掉它。抠图的下一步经常是再抠一张。每次抠完都往用户屏幕上摔一个窗口，是在替用户假设他只抠一张。shelf 网格和主窗口列表已经是结果的落点，点一下就开预览——**要看的人去看，不看的人不被打断**。
- **代价**：拖进一堆图之后，用户不看就不知道哪张失败了。这个由主窗口那条按整图计数的进度条和失败行接住（红三角 + 原因），不需要一个会自己跳出来的窗口。

## 2026-07-28 — CoreMLEngine 与 ModelRegistry：manifest 只有一份、zip 只用 ditto、编译只做一次

- **决策**：PluckKit 新增 `CoreMLEngine`（同步 `mask(for:)`）与 `ModelRegistry`（manifest 解析 + 下载 + SHA256 + 安装），`models/manifest.json` 落地两条 BiRefNet_lite 记录，CLI 的 `--model` / `models list` / `models pull` 接到它们上面。
- **`.cpuAndGPU` 写进构造函数，不给调用方选**：ANE 编译不了替代 deform_conv2d 的那条 gather 链——lite 上是快速失败，swin-large 上是 0% CPU 挂 37 分钟（research.md 附录 A.6）。这不是性能取舍，是一条"选错就永远不返回"的约束，所以它属于引擎自己，不属于配置。
- **`CoreMLEngine.load` 是 async，`mask` 仍是同步**：`MLModel.compileModel(at:)` 的同步写法 macOS 13 起废弃，用它就换不到零 warning。加载因此变成一次 async 工厂，推理保持同步——`MattingEngine` 那条"引擎说清自己是阻塞的，由 `PluckQueue` 决定它在哪跑"的约定不变。编译产物缓存在 `~/Library/Caches/Pluck/CompiledModels/<id>.mlmodelc`，按源文件 mtime 判新旧：冷启动 5–10 秒只付一次（实测首次 55 秒含编译，之后整条命令 1.8 秒）。
- **`CoreMLEngine` 是 class + `@unchecked Sendable`**：`MLModel` 不是 `Sendable`，但 `prediction` 允许多线程调用，而 `PluckQueue` 本来就开 2–4 路。包成 actor 会把管线里唯一允许跑宽的一段重新串起来。
- **fp16 输出用 vImage 转 Float32，不用 Swift 的 `Float16`**：后者在 x86_64 macOS 上不存在，而 `vImageConvert_Planar16FtoPlanarF` 处处都有；`MLMultiArray` 的下标则会给一百万个元素各装一个 NSNumber。
- **manifest 在仓库里只有一份字节**：真身放 `Sources/PluckCLI/Resources/manifest.json`（SwiftPM 只接受 target 目录内的 resource），`models/manifest.json` 是指向它的符号链接。反过来放（真身在 models/、target 内放软链）会被 SwiftPM 原样拷成一条相对链接，在 `.build` 里就断了——实测断在 `.build/models/`。两份实体文件加一条"别忘了同步"的注释不算方案。
- **zip 两端都用 `/usr/bin/ditto`**：Foundation 在 macOS 上没有公开的 zip 读写（`AppleArchive` 说的是 .aar），而 `.mlpackage` 是目录包，需要保住结构与扩展属性。打包脚本 `ditto -c -k --keepParent`，安装时 `ditto -x -k`，同一个工具、无第三方依赖。
- **`package-models.sh --check` 不重新打包**：ditto 的 zip 不是逐字节可复现的（mtime 与目录顺序会渗进去）。该问的是"manifest 描述的是不是我正要上传的那个文件"，不是"重打一遍哈希是否相同"。manifest 里的 sha256/bytes 一律由脚本从真实 zip 生成，不许手填占位值。
- **新增三个 `PluckError.Kind`**（`model_load_failed` / `model_download_failed` / `manifest_invalid`）：CLI 把前者与 `model_missing` 一并解析为 exit 3——对写脚本的人来说"模型没装"和"模型装了但用不了"是同一件事：这个模型现在不可用。App 侧 `PluckFailure` 暂时把它们并进 `.unknown`，等 app 长出下载 UI 再给它们自己的文案。
- **安装是一次 rename**：先解压进 `Models/.staging-<uuid>/`，校验通过后整个目录一次移入 `Models/<id>/`。半个模型目录在下一次启动会被读成"已安装"。

## 2026-07-28 — 两处对外契约变化：PNG 带色彩 profile，--json 补全失败词汇表

- **背景**：Kit/CLI 审查修复批（merge commit 见 git log）中两条修复改变了外部可见行为，按惯例记录。
- **PNG 输出现在携带输入的色彩空间**：此前所有输出被静默压进 DeviceRGB（事实上的 sRGB 语义），Display P3 照片的出画面色域被裁剪。现在工作空间跟随输入的 RGB profile（非法的位图目标 profile 回退 sRGB），`--background` 的 hex 颜色按 sRGB 解释后转入工作空间——同一个 #ff6600 在 P3 输出里仍是同一个颜色。对"把主体原样还给你"的工具，这是正确性而非增强。
- **`--json` 的失败词汇表补全**：setup 阶段失败（坏参数/未知模型）此前 stdout 零输出，现在发一条 run 级记录（`ok:false` + slug + message）；条目级失败记录新增 `output` 与 `engine` 字段。面向 agent 的接口里，"失败但不说哪个文件、哪个引擎"等于要求调用方解析英文散文。
- **shelf 面板即投放目标，引导是结构不是横幅**：对 12 款 menubar app（重点 Dropover/Yoink/Dropzone）两轮调研确认：无一家用常驻投放横幅。投放条删除；有内容时网格首格为虚线幽灵格（"下一张落在这里"+ ⌘V 提示），空态为同语法撑满版；底栏取消，控件并入标题行；状态消息改为仅在有话可说时出现的浮动材质条。缩略图右键菜单（Copy/Save As/Show Preview/Delete）补齐单项删除。产品差异注记：Dropover/Yoink 是"拖出即用完"的暂存架，Pluck 是"拖出后仍保留"的结果档案——因此不抄"拖出即移除"。

## 2026-07-28 — 断点续传用手写 Range，信任仍然只来自哈希

- **决策**：`ModelRegistry` 的下载改为可续传。字节边收边追加到 `Models/.downloads/<id>.partial`，重试时发 `Range: bytes=N-` + `If-Range`（首次响应的 ETag，没有 ETag 用 Last-Modified，两者都没有就整下）。206 追加，200 丢弃 partial 重来，416 丢弃后自动重试一次。`ModelDownloading` 协议随之改为 `download(from:into:onProgress:)`——目的地由调用方指定。
- **不用 URLSession 的 `resumeData`**：它是不透明 blob，只在任务被**取消**时才产生（连接断了没有，进程死了更没有——而这恰好是 `pluck models pull` 最需要的两种中断），而且没有任何一部分可以在测试里断言。三个明文 HTTP 头可以：`Scripts/serve-models.py`（约 130 行 python stdlib）实现 Range/If-Range/ETag/206/200/416，集成测试起它、造 300 KB 资产、验证三个场景，全程 127.0.0.1，真网零依赖。
- **校验逻辑一字不动**：续传只负责把字节凑对，"这是不是正确的字节"仍然是完整文件上的一次 SHA256。哈希失败时**删掉 partial**——对已经哈希错的字节继续追加，只能得到一个更长的错文件。这是唯一不允许续传的失败。
- **partial 放在 `Models/.downloads/` 而不是 `/tmp`**：临时目录会被系统清理，也会被 Pluck 自己的启动清扫清掉，而那正好是用户最可能要续传的时刻（退出之后）。同卷还意味着安装是一次 rename 而不是 94 MB 的拷贝。
- **下载器从 download task 换成 data task + delegate**：download task 失败时什么也不给——它收到的字节在系统临时文件里，失败即删，而那正是续传要保住的状态。现在每一块字节到达即落盘，90% 处被打断就留下 90%。
- **实测**（真实 release 资产 82 MB）：pull → `kill -9`（51 MB）→ 再 pull，第二次进度从 61% 起跳并安装成功，说明服务器认了 range 且拼接后的哈希仍然通过。

## 2026-07-28 — EngineCatalog 下沉 PluckKit，app 学会切引擎

- **`EngineCatalog` 从 PluckCLI 移进 PluckKit**（`EngineDescriptor` 一起公开），CLI 侧只剩 `Engines.catalog = EngineCatalog.bundled(in: .module)` 这层薄壳与原样的输出格式。理由：CLI 和 app 要问的是同一个问题（"这台机器现在能用哪些引擎"），两份实现就是两次对"用户装了什么"给出不同答案的机会。
- **app 的 manifest 由 `Scripts/bundle.sh` 拷进 `Contents/Resources/`，不进 SwiftPM 资源包**：SwiftPM 会把 target 里的符号链接原样拷成断链（实测断在 `.build/debug/Pluck_PluckApp.bundle/`），而两份实体 manifest 加一句"记得同步"不算方案。于是 manifest 走签名这一条路进 app——这本来就是 §4.8 的信任链原文：签名担保 manifest，manifest 钉死 URL 和哈希。**代价**：`swift run PluckApp` 起的开发壳没有可下载模型列表。这不是缺陷而是诚实答案——没有任何东西为那份 manifest 背书。
- **`Preferences.engineID`（默认 `vision`）存的是 id 不是枚举**：引擎列表 = manifest + 磁盘现状，两者都不是编译期固定的。指向已删除模型的 id **不在这里被擦掉**，而是在使用时回落——一个会自己偷偷改写的偏好比一个暂时无法满足的偏好更糟。
- **回落而不是报错**：`EngineProvider` 是 actor（首次加载 = 5–10 秒 Core ML 编译，必须只发生一次，第二个拖入者等第一个的 Task）。模型加载失败一律回落 Vision + 一条状态消息，不抛错——用户的图仍然完全可以抠。选中的引擎保持选中：下次拖入会再试一次，在 Settings 里重装完就自动恢复。
- **加载中的提示复用现有 status 机制**：占位卡先进网格（拖入立刻有位置），然后一句"Getting the model ready…"，加载完即撤。Vision 和已加载模型这条路上一个字都不说——常见情况必须保持安静。
- **Settings 的 Models 一节：删除就是删除，不进废纸篓**。废纸篓是给用户自己造的、可能想要回来的东西准备的；模型是一份 94 MB 的缓存，URL 就在 app 里，随时可以再下。留在废纸篓等于让"释放了 94 MB"实际上意味着"挪了 94 MB"。cutout 是反面例子——那是用户的成果，所以它才有确认。
- **下载/取消/删除全部走 `ModelRegistry`**：app 内不出现第二份下载逻辑，也就不出现第二处可能把哈希校验写错的地方。取消保留 partial，再点 Download 是续传而不是重来。
- **离线声明改写而不是留着**：旧文案"makes no network requests"在有模型下载之后就不再为真。新文案把真正的承诺（图片不离开这台 Mac）和唯一的例外（你点名要的模型）一起说出来——把唯一的例外说清楚，才是让其余部分可信的办法。

## 2026-07-28 — 引擎是题材分工：Settings 说人话，预览面板长出 Re-pluck 菜单

- **背景**：v0.3 让 app 能切引擎，但那次交付的说法是错的——引擎 Picker 埋在 Settings，列表里写着 `BiRefNet_lite` 和 `BiRefNet_lite matting`（对用户零信息量），切换之后结果上也看不出用了谁。而实测（research.md A.6 + 维护者目检）说明这两个模型**不是质量梯度而是题材分工**：lite 出干脆硬边，半透明物（酒杯）被抠成实心；lite-matting 保真实透明度与软发丝，软边带像素占比 4.4% vs 1.2%。同体积、同速度、同 license。
- **不做 Fast / Best 二元**：这是最诱人的简化，也是唯一会让用户丢掉想要的那张图的说法。"Best" 会让所有人一律选它，然后 logo 和产品图的边缘变糊；"Fast" 会让没人再点开另一个。标签因此按题材取名——**Detail**（干脆边）与 **Matting**（软发丝、真透明），配一句讲**出画结果**而不是讲模型结构的描述。速度提示（instant / ~1–2 s per image）与体积留在行里，但不再是选择的主轴。
- **人话映射住在 app 层（`EngineLabels`）**：PluckKit 的 `EngineDescriptor.summary` 是 CLI 打印的开发者文案，`--model birefnet-lite-matting` 是 agent 精确输入的接口，两者都不该被改写成给人读的名字。CLI 完全不动。manifest 新增而 app 还没写文案的模型回落到 `displayName`——没人写过的文案不是隐藏这个引擎的理由。
- **Settings 的 Models 一节保留列表、换说法**：行首人话标签 + 题材描述，`BiRefNet_lite · MIT · 83 MB · ~1–2 s per image` 降为 caption（在意 provenance 的人仍然找得到）。Vision 也占一行、无控件——它没有下载动作，但它是用户**已经有**的那个选择，此前它在这一节里根本不存在。三态控件与体积不变。
- **Re-pluck 菜单在预览面板，不在 Settings**："这条边缘对不对"这个念头只在看着结果的那一刻发生，让人为此去开设置、改默认引擎、再把图拖一遍是把一次判断拆成四步。菜单只列**这张图还没走过的**引擎（已走过的没有新东西可产），未安装的括号里显示体积——下载是点击的真实代价，比速度更该先说。
- **结果并列插入，不覆盖**：两种边缘是两个答案，不是一个答案的两次尝试。覆盖会让"再看一眼另一种"要付一次重抠的代价，而用户在两张同时在屏幕上之前根本无法判断自己要哪个。完成后预览面板切到新条目（问是在这个面板问的），旧条目原样留在网格里。
- **重抠的输入是条目存下的 `original.png`（长边 1200px）**，所以 24MP 照片重抠出来是 1200px 的图。为一个多数条目用不到的功能给每张图再存一份全分辨率原图，会把归档体积翻倍；诚实的解法是把文件再拖一次，代价是一次拖拽。这条写进 `AppModel.repluck` 的注释。
- **重抠**指名引擎**时不回落 Vision**：拖入时回落是对的（用户要的是把图抠出来），重抠时是错的（用户点的是"用 Matting 试试"，给他一张已有的 Vision 副本不是这个问题的较小答案）。因此模型加载/下载失败一律是这次任务失败 + 一条状态消息。顺带给 `PluckFailure` 补了 `modelUnavailable`——v0.3 那条"等 app 长出下载 UI 再给它们自己的文案"的欠账在这里还上。
- **出身标注只标非默认引擎**：Vision 是默认也是绝大多数条目，全标等于在每一行印同一个词，标签就此不再被读。主窗口行副标题（尺寸 · 时间 · 引擎）与预览面板 Cutout 角标旁各一处。
- **`RecentItem` / index.json 新增 `engineID` 与 `sourceID`，decode 容忍缺失**：`engineID` 记的是**实际跑的**引擎（`engine.id`）而不是偏好里写的，否则一次回落就会让条目谎称自己的出身；`sourceID` 是同一张图的血缘，让"这张图还没走过谁"在重启后仍然成立。两者都用 `decodeIfPresent` + 默认值（vision / 自己的 id）——旧 index 是用户的全部历史，合成的 `init(from:)` 会在第一个缺失键上抛错，而 `load` 把抛错读成"没有索引"，那就是**升级后的第一次启动把归档清空**。这条在 `CutoutArchive.Record` 上写成了规则，并有专门的旧格式测试。

## 2026-07-28 — 齿轮直接开 Settings，About / Quit 搬到状态项右键菜单

- **shelf 齿轮回到普通按钮，点击直开 Settings**：齿轮在这台机器上到处都意味着"设置"，中间夹一层只为多挂两项的下拉，等于让最常见的那次点击付两下。`ShelfMenuButton` 删除。
- **About / Quit 搬到状态项右键菜单**（左键开面板、右键出菜单是菜单栏 app 的标准分工，也是用户找它们的地方）。Settings **不重复**放进去——齿轮已经一步到位，一个窗口两个门是多的那个。mainMenu 里三项原样保留：⌘, / ⌘Q 的解析仍然只走那里。
- **实现走 `StatusItemDropView.onSecondaryClick` 而不是 `button.sendAction(on:)`**：拖放目标是铺在状态项按钮上的一层 NSView，命中测试把所有鼠标事件都给了它，按钮自己的 action 根本收不到。右键时临时挂上 `statusItem.menu` → `performClick` → 立刻摘掉；常驻挂菜单会让 AppKit 连左键一起吞掉，shelf 就再也打不开了。右键还要把 `swallowIconClick` 复位——dismiss monitor 已经为这同一次右键关掉了 shelf 并上了膛，否则下一次左键会被吃掉。

## 2026-07-28 — 预览面板的一次性重抠菜单变成常驻引擎切换器

- **循环箭头按钮 → 文字引擎切换器**：维护者对着实机截图的反馈——刷新图标看不出是"换模型"，而"只列没用过的引擎"的菜单用一个少一项，学不会也读不出当前状态。新模型是**"用哪个引擎看这张图"的持久切换器**：工具胶囊第三键显示当前结果的引擎人话名 + chevron（既是状态也是入口），菜单**永远列全部引擎**、当前项打勾、未安装的括号里仍是体积。
- **切换优先复用已有兄弟结果**：按血缘（`sourceID`）+ 引擎在 recents 里找，找得到就把预览面板切过去，**不重算**；找不到才走原来的重抠（含未安装先下载）。两张边缘本来就并排躺在架子上，来回比对不该付任何代价。规则抽成纯函数 `AppModel.sibling(of:engine:in:)` 配测试，"切到已有"与"算一张新的"两条路径各有一条。
- **角落胶囊回退为纯 "Cutout"**：出身信息现在挂在切换器这个**能改它**的控件上，角标再说一遍就成了同一事实的第二个、更小声的标签。`EngineLabels.cutoutBadge` 与 `Cutout · %@` 一并删除。主窗口行副标题的引擎标注保留——那里没有别的载体。

## 2026-07-28 — 视觉语言 v2：吸色玻璃、零细线、卡片格、体量表

- **背景**：维护者对着实机截图的判断是"看起来像 Mac 原生组件堆砌出来的产品，没有设计感"。把我们自己的 p3 原型和三张参考图（Dropover 的 power/instant-actions、Yoink 主图）并排看，差距不在缺功能而在四件具体的事：面板几乎不透明、到处是 1px 细线在分区、结果格是"玻璃上的洞"而不是物体、所有控件都停在系统默认的 28pt 上。v2 是这四件事的修法，**交互结构一律不动**。
- **面板吸色玻璃**：shelf 背板 `.popover` → `.hudWindow`（仍是 `.behindWindow`）。`.popover` 是 NSPopover 自己的材质、几乎不透光，面板读起来是"一个浮着的浅灰盒子"；p3 与 Yoink 的面板都被身后的壁纸染了色，`.hudWindow` 是 macOS 14 上唯一能到那个透光量的材质。它跟随 effectiveAppearance，所以浅色下是浅玻璃而非"深色 HUD"。圆角 16→20（`maskImage` 与 SwiftUI 侧同步）。阴影仍走 `NSPanel.hasShadow`：自绘要靠一个更大的透明窗口把阴影画在里面，会毁掉拖放目标的 bounds，换来的阴影用户还分不出与系统的区别。
- **零细线**：面板与主窗口内所有 `Divider()` 与 hairline 描边删除（列表行间分隔线、列表卡描边、玻璃圆钮的白色 rim、预览工具胶囊的 rim）。参考产品一根细线都没有，全部靠填充、圆角、留白分层。代价是行分界在静止时消失——补法是行 hover 时给一块圆角 10 的 quaternary 填充：分界只在用户正在瞄准某一行的那一刻才是问题。玻璃钮丢掉 rim 的那份对比由材质补：`.regularMaterial` → `.thickMaterial`。
- **结果格变卡片**：过去缩略图是"棋盘格矩形被裁个圆角直接贴在玻璃上"，等于在面板上挖洞；p3 画的是实心浅色卡片，棋盘格和主体在卡**里**。这个读法才让一张透明 PNG 看起来像可以拿起来的东西，也才给 hover 抬起（scale 1.02 + 阴影加深）一个可抬的对象。卡面是纯色不是材质——玻璃上再叠玻璃会让整格糊掉。主窗口行缩略图同语言（小一号的同一张卡）。
- **棋盘格降到听不见**：8pt / 13% 对比 → 6pt / 约 5%（浅色白 × `0xF3F3F3`，深色沿用系统深灰对）。旧参数是视觉噪音最大的单一来源：一格只有 90pt 宽，任何东西排十一列都是花纹，而这块格子的全部职责是说"这里没有东西"。测试的对比带从 `0.01–0.2` 收到 `0.03–0.07`，并加一条方格尺寸的断言——两个半边都必须成立，5% 对比画在 8pt 上在缩略图尺寸仍然是条纹。
- **体量表**：圆玻璃钮与图标钮 28→32pt（hover 圆形填充、按下 0.96），预览工具条 36pt、引擎切换器加胶囊填充（一个裸词夹在两个圆钮之间读起来是说明文字不是控件，边框没了之后填充是唯一还能说"可按"的东西），面板边距 16→20、顶 12→16，Settings 图标砖 30→36pt、选中圈 18→22pt，Export All 改 `.large` 胶囊。
- **Settings 图标砖的淡珊瑚渐变不计入"每屏一个染色元素"**：8%→16% 的对角洗色是**表面色**，不是被染色的元素；这一屏可数的染色元素仍然只有珊瑚选中勾（选中行的 symbol 用珊瑚是同一个元素的延伸）。买到的是一列属于 Pluck 的砖，而不是三个哪个设置面板里都有的灰方块。
- **Settings 不适用零细线**：§4.7 的玻璃分级按表面分级——面板是我们自己画的，而 Settings 是用户**主动去找**的窗口，应该长得像这台机器上别的设置窗口。grouped `Form` 自带的分组盒子与行分隔保留：要去掉它们就得把 Form 重新实现一遍，等于拿用户来这里要找的那个原生感去换一套自家风格。
- **数字集中在 `DesignTokens.swift`**：半径（面板 20 / 卡 14 / 行 10 / 缩略图 8）、阴影三档、棋盘格参数、控件尺寸全部一处定义，注释写清"这些数字来自 p3 与参考产品的对照，改这里=改全局"。同时把三条能解释这些数字的规则写在文件头（无细线、半径随表面递减、控件不小于 32pt），否则下一个人只会看到一堆魔数。

## 2026-07-28 — Liquid Glass：26+ 用真玻璃，14 回落材质，内容层永不上玻璃

- **背景**：维护者对着实机截图的判断是面板"还是纯色背景"，没有 macOS 最新那种半透明模糊玻璃质感；而且上一轮 v2 只修了 shelf，其他表面没跟上。查下来原因很直接：**全程用的是 macOS 14 时代的 `NSVisualEffectView` / `Material`**。`Material` 只做背后内容的模糊，Liquid Glass 还做折射与边缘高光，后者才是"透镜浮在壁纸上"而不是"磨砂卡片贴在壁纸上"的那个差别。本机 SDK 是 MacOSX26.5，四组 API（AppKit `NSGlassEffectView` / `NSGlassEffectContainerView`，SwiftUI `.glassEffect(_:in:)` / `GlassEffectContainer` / `.buttonStyle(.glass)` / `.glassProminent`）先写了个 probe 包确认能编译，再铺开。
- **一律 `if #available(macOS 26.0, *)` 双写，不用 deprecated 绕过**：部署目标仍是 macOS 14，而 14 上没有任何东西能模拟折射。两个分支就是两套设计，只在**形状与尺寸**上一致：26 是透镜，14 是材质。没有第三种写法——弱链接加运行时 `NSClassFromString` 能少写一遍，但会把"这个控件在 14 上长什么样"变成没人复核过的问题。
- **玻璃的边界是分层，不是浓度（§4.7 的收紧版）**：容器与控件用玻璃，**内容层一律不加**。抠图结果、棋盘格、和承载它们的卡片保持实色——卡面如果是玻璃，就等于在一张"卖点是能透过去看"的图后面把壁纸又模糊一遍，两层透明叠在一起谁也读不清。这条现在写在 `Glass.swift` 的文件头上，并且由"用哪个 API"来强制：`pluckGlass` / `GlassGroup` / `PanelBackdrop` 是玻璃的三个入口，内容层的代码里不出现它们。
- **AppKit 侧：背板与拖放目标拆开**。shelf 的 `ShelfBackdropView` 过去**自己就是**那块 `NSVisualEffectView`，于是"面板由什么做成"和"面板接受什么拖放"绑死在一个类上。现在它是普通 `NSView`，只管拖放，玻璃由 `PanelBackdrop.install` 装进去——AppKit 找拖放目标是命中测试之后**沿 superview 链上走**，所以上面那层是 `NSGlassEffectView` 还是 `NSVisualEffectView` 都到得了。`NSGlassEffectView` 用 `contentView` 而不是 `addSubview` 装载：头文件明说只有 `contentView` 保证在效果层里，别的子视图 z-order 不保证。
- **圆角归玻璃管**：26 上 `NSGlassEffectView.cornerRadius` 同时定形与裁剪，`maskImage` 和手写 layer 圆角一起退休（14 分支照旧，`.behindWindow` 的模糊在图层树之外合成，只有 `maskImage` 够得着）。副作用是预览面板按图片长宽比 `setContentSize` 时圆角自动跟着走，不必再手工同步。
- **玻璃上不再叠 macOS 14 的阴影**：Liquid Glass 自带接触阴影与边缘光，再压一层 `controlShadow` 会变成一圈黑晕——这是"14 的阴影被留在 26 的控件上"最明显的痕迹。新增 `Tokens.glassShadow`（0.10 / 4 / y1），26 分支统一用它。`.interactive()` 玻璃自己会在按下时缩放发亮，所以 `PressableButtonStyle` 在 26 上停用自己的缩放（`scales: false`），一个手势只演一次。
- **一条工具栏是一块玻璃，不是三块**：预览工具胶囊在 26 上是单个 `.glassEffect(.regular, in: Capsule())`，里面的 Copy/Save 仍是带 hover 高亮的裸 glyph——`.buttonStyle(.glass)` 挨个套会是玻璃叠玻璃，而系统自己的工具栏就是"一条透镜 + 若干 glyph"。真正独立站在图片上的控件（卡片 hover 的 Copy/Save、预览关闭钮、对比手柄）才用整块玻璃，其中成对出现的用 `GlassEffectContainer`（`Tokens.glassMergeSpacing`）让两块透镜在出现时汇成一个物体。
- **引擎 chip 必须换实现，不是换材质**：截图核对时发现 26 上 `.menuStyle(.borderlessButton)` 不再遵守 `.menuIndicator(.hidden)`、并且丢掉 label 自己的背景——chip 渲染成一个前面挂着孤零零 chevron 的说明文字，完全不像可按。26 分支改成 `.menuStyle(.button)` + `.buttonStyle(.glass)` + 胶囊边框，chevron 交还系统；14 分支原样保留手绘 chevron + `.quaternary` 胶囊。这条是"逐面截图核对"这个验收方式抓出来的，纯读代码看不出来。
- **主窗口仍是标准窗口材质**（§4.7 玻璃分级不变：背后可能是任意窗口而非壁纸，可读性优先）。它拿到的是**控件语言**而不是更多玻璃：Export All 在 26 上是 `.glassProminent` + 珊瑚 tint（形状与 tint 都不变，只是从平面胶囊变成染色透镜），行 hover 的圆钮本来就走 `GlassCircleButton`。行 hover 填充与投放条虚线**不上玻璃**——它们身后是不透明的窗口底，玻璃在那里没有东西可折射，只会变成一块灰。
- **Settings 上玻璃的只有按钮**：Form 的原生分组与自带分隔保留（沿用 v2 的理由），但 Download / Delete / Cancel / Clear recent cutouts 一律换 `.buttonStyle(.glass)`（26）。理由是反过来的：在 26 上 `.bordered` 已经是旧控件，只有这一个窗口留着它，"原生"就变成了"过时"。四个按钮一起换，避免一屏里两套按钮语言。
- **菜单不动**：引擎切换菜单与状态项右键菜单都是系统菜单，26 自带新观感，代码里没有自绘样式挡着，确认即可。

## 2026-07-28 — 产品审计三决定：主窗口画廊化 + 选择模型、隐私声明三合一、不做 app 内语言切换器

- **主窗口从"文件列表"改成"图像画廊"**：窗口存在的理由是抠图结果，而结果的好坏全在边缘上——旧版把它画成一行文字末尾的 44pt 邮票，等于把证据放在最小的位置。现在是 shelf 那张卡（`CutoutCard` 从 `ShelfView` 提为共享）铺成 `LazyVGrid(.adaptive(132...150))`：同一个物体在两个表面上是同一种画法，窗口可缩放时列数由窗口自己定。三样东西跟着列表一起删：①常驻虚线投放条——它在教一个用户刚刚已经做过的手势，整窗本来就是投放目标（拖拽时整块内容区亮 accent 边），空态仍然把话说全；②"10 cutouts" 计数——格子本身就是那些抠图，给照片配一句"照片"；③行尾 ✓ Done，连同 `AppModel.batchItemIDs` / `isBatchRunning`——网格里占位卡在**原格**变成结果就是那个 ✓，把它限定在当前批次的那份状态没有别的用处了。
- **选择模型是规则不是画法，所以抽成纯类型**：`GallerySelection`（单击选中/再点取消、⌘点增删、⌘A 全选、Esc 清空）+ `exportTargets`（有选中就是选中项、按网格顺序；没有就是全部）。导出按钮跟着说 "Export 3…"（复数走 catalog）——一个写别的东西的提交型按钮是最不能有的东西。**平击必须覆盖多选而不是并入**（否则想重来的人导出了四张），**删掉的条目必须离开选择**（否则按钮说三张、只写两张）：两条都有测试。⌘A 在 key monitor 里截，理由和 ⌘V 一样——`selectAll:` 是文本操作，这个窗口里没有文本；Esc 只在有选中时吞，没选中时吞掉 Esc 等于从别人手里抢走一个键。
- **隐私声明三合一**：Models 节脚的盾牌行、History 说明里的 "and never uploaded"、窗底那句，三处说的是同一个承诺。同一句小字重复三遍不会变成三倍可信，只会读成免责声明；留最完整的窗底那句。History 说明同时压成一句人话——"Application Support" 是开发者对这台机器的心智模型里的目录名。
- **引擎行 chips → 一行 caption**：三枚胶囊让一行里挤了四种字号，围着那句唯一写给关心 provenance 的人的信息造了一堆家具。改成 tertiary 小字 `BiRefNet_lite · MIT · 83 MB`。Vision 的 "Built-in" 直接删——它的 blurb 已经说了 built into macOS，chip 是同一句话再穿个胶囊。
- **不做 app 内语言切换器**：多语言走系统的"按 app 设定语言"（系统设置 › 通用 › 语言与地区 › app 语言），这是 mac 上的惯例，也是 String Catalog 的机制本身；app 内再放一个切换器等于把系统已经提供的选择复制一份，还要自己处理"改完请重启"。本轮做的是它的地基：全 app 扫一遍排版弹性（该换行的 `fixedSize`、按钮不定宽、窄面板里让标签先让位给控件），并用把所有英文串加长 30% 的伪本地化包实测了 Settings / shelf / 主窗口三个表面，无一处截断。

## 2026-07-28 — 主窗口沉浸玻璃：推翻"主窗口用标准材质保可读性"

- **决策**：主窗口改成和 shelf 一模一样的玻璃——`fullSizeContentView` + 透明标题栏 + `backgroundColor = .clear` + `isOpaque = false`，背板走同一个 `PanelBackdrop`（26+ `NSGlassEffectView`，14 回落 `NSVisualEffectView` `.underWindowBackground`/`.behindWindow`），圆角传 0 交给 `.titled` 窗口的窗缘去裁。**这条推翻 §4.7 的"玻璃分级"与 2026-07-28 Liquid Glass 那条里的"主窗口维持标准窗口材质"**，两处都已在 product-plan 里划掉并标注。
- **为什么原来的理由不成立**：原话是"背后可能是任意窗口而非壁纸，可读性优先"。这句话把 Liquid Glass 当成了"开一个洞"。它不是——它染色、折射、给自己的边缘打光，p4 那张深紫底之所以读得清，靠的正是 tint 而不是不透明度。**深 tint 玻璃本身就是可读性方案**，浓度是 `Tokens` 里的一个参数，不是一个要按表面分档的等级。实测：一块花花绿绿的聊天窗口垫在后面，亮/暗两模式下空态标题、副标题、珊瑚 Export 按钮都清清楚楚。
- **红绿灯留，标题字去**：这是唯一保留标准窗口部件的地方，理由是它可缩放、可以被留在别的窗口后面——关窗和缩放是这类窗口的操作方式，自绘一套只会更糟。但 `titleVisibility = .hidden`：一个没有标题栏背景的玻璃面上飘着 "Pluck" 四个字，读起来是一条忘了画自己的标题栏。`window.title` 仍然照设并走 catalog——Mission Control、Window 菜单和 VoiceOver 用的是它，看不见不等于不存在。
- **内容不滚到红绿灯底下，改留 28pt**：系统那套"内容滚过标题栏"靠的是标题栏自己那层模糊材质在中间垫着。我们没有那层，卡片滑到三颗按钮下面就是纯粹的重叠。28pt 安静的玻璃比一次视觉事故便宜。
- **所有系统底让位**：滚动区 `.scrollContentBackground(.hidden)`（`NSScrollView` 会画窗口底色，而这个窗口已经没有底色了）、底栏删 `.background(.bar)`（材质条是用来把页脚从**不透明**内容区里分出来的；铺在玻璃上就是第二块更灰的玻璃）、空态删 `.quaternary` 洗色。**卡片仍然是实色**——内容层原则一个字没动。
- **空态的虚线框一并删掉**（这条是自己判断的，报告里写明）：它是"画廊化"那轮删掉的常驻投放条长满整窗的版本，两个问题——`.quaternary` 是一块系统灰，糊在一块"颜色应该来自身后"的表面上；虚线是面板内细线，v2 的零细线规则在别处已经执行得很干净了。整窗本来就是投放目标，拖拽时那圈 accent 边才是对这个手势的回答，而它只在为真的时候说话。剩下的空态就是图标 + 两行字，直接站在玻璃上。

## 2026-07-28 — 做 app 内语言切换器，而且免重启：推翻同日"不做"那条

- **决策**：`Preferences.languageID`（`system` / `en` / `zh-Hans`，默认 `system`），Settings 顶部一行 `Language` 选择，**改完当场生效，不要求重启**。**这条推翻同日"产品审计三决定"里的"不做 app 内语言切换器"**。
- **为什么推翻**：原来的理由是"系统已经提供了按 app 设定语言，再放一个是复制"。这个理由漏掉了它服务的那个人——**系统是英文、但想用中文界面的用户**。这个人真实存在（维护者本人的使用场景之一就是反过来的版本），他不会为了一个抠背景的小工具去改系统语言，而系统那个按 app 的开关在「系统设置 › 通用 › 语言与地区 › 应用程序」下面三层，是绝大多数人从没打开过的抽屉。"系统已经有了"在这里不是"用户已经有了"。
- **免重启是这条能成立的前提**：原来那句反对里真正对的部分是"还要自己处理'改完请重启'"。一个需要重启的语言开关确实不如系统那个（系统那个也要重启，但它至少会自己弹提示）。所以做法不是加个开关加句提示，而是把 `L` 改成**路由**：`L.Route` 指向 `<id>.lproj` 的 `Bundle`，`Language` 单例持有当前 id 并且是 `@Observable`。SwiftUI 侧零成本——view 的 body 调 `L.s`，`L.s` 顺手读一下 `Language.shared.id`，观察依赖就注册上了，没有任何一个 view 需要记得做什么。
- **`L.s` 里那次"顺手读"是有意的**，写在注释里：它是"问我要句子的人，就是想在语言变了以后被重新运行的人"这句话的代码形式。它由 `Thread.isMainThread` 守卫，因为同一个函数也会在解码队列上被调用（`PluckService` 给抠图结果起名字），那里既没有观察在进行也没有东西要订阅。路由本身是 `nonisolated(unsafe)`，因为写入是整体替换两个不可变引用：一次和切换赛跑的查表拿到的要么是旧句子要么是新句子，两个都是句子。
- **AppKit 那半靠通知**：`NSApp.mainMenu`、各窗口的 `title`、状态项的无障碍标签都是"建一次就留着"的副本，副本只能替换。`.pluckLanguageDidChange` 的处理器就是这份清单，短到可以维持诚实。状态项右键菜单不在清单里——它每次点击都重建。Settings 与 About 还要重新量一次高度（英文比中文多占一到两行），量之前先 `Task` 让一格并 `layoutSubtreeIfNeeded()`：观察是**安排**更新不是**执行**更新，当场读 `fittingSize` 量到的是它正要不再显示的那些句子。
- **选项文字用它自己的语言写**：`English` 永远是 English，`简体中文` 永远是简体中文，两个都是 `Text(verbatim:)`、不进 catalog——它们不是文案，一个"改进"了它们的译者会把这个控件弄坏。只有 `System` 跟随当前语言，因为它命名的是一种行为而不是一种语言。理由是这个控件的用户按定义就是当前语言正在辜负的那个人：一个对着看不懂英文的用户写 "Chinese, Simplified" 的菜单，只对不需要它的人有效。
- **翻译完整性写成测试**：解析 `Localizable.xcstrings`，断言每个 en key 都有 zh-Hans 值（plural 变体逐个数）。漏翻的失败模式是"渲染出一句正确的英文"——在一屏中文里它不会报错、不会崩、只会看起来像忘了做，截图里最容易滑过去的那种。

## 2026-07-28 — 不到 1.0 不发布

- **决策**：废除 v0.1/0.2/0.3 的阶段发布计划，单一 1.0 门槛——所有剩余项（Sparkle、Quick Action、SKILL.md、decontamination、营销物料、发布工程）做完才第一次公开发布。
- **理由**（维护者）：不发半成品。分阶段版本号曾用于组织工作，继续保留只会制造"可以先发一版"的错觉。工作排序不变，变的是"完成"的定义。
- **影响**：仓库公开但无 Release/无安装渠道的状态持续到 1.0；models-v1 资产 Release 不受影响（它是依赖，不是产品发布）。
