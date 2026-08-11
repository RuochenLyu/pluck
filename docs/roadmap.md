# Roadmap 与当前状态

> 本文件是唯一的进度真相源：阶段推进、里程碑范围变化时更新这里。
> 产品定义与架构见 [product-plan.md](product-plan.md)，决策记录见 [decisions.md](decisions.md)。

## 当前状态（2026-08-11）

- **第三轮打磨（交互手感）**：单击选中延迟修复（双击改为并行手势，不再阻塞单击）；卡片去 hover 抬升/阴影（tile 静态，Finder 语义），改为**常驻 footer**（名称/尺寸 + 拷贝/存储小图标，CleanShot 的信息架构、原生实现）；**单击即预览**——inspector 默认打开、状态持久（Finder 预览栏语义）；⇧ 范围多选（锚点规则）；**列表视图**（`List` 原生选择语义 + 斑马纹 + 行尾快捷按钮 + focus 修复），toolbar 连体视图切换组（`ControlGroup`）；导出改图标按钮（`square.and.arrow.up`），批量进度移入 toolbar（spinner + n/m），窗口标题不再绘制；外观偏好（跟随系统/浅色/深色，即时生效）；对比图跟随图片比例至黄金比例 0.618。290 全绿。
- **图标定稿（2026-08-11，见 decisions.md 同日）**：cat-1——珊瑚猫走出照片卡、卡留猫形洞；三图层进 `Packaging/icon/`，`make-icon.swift` 改为分层合成（构图参数对真实 Dock 调定），bundle 管线自动出新图标。**待办**：Icon Composer 玻璃版（素材已备，五分钟 GUI 摆位）；伪本地化复跑。

## 历史状态（2026-08-10 晚）

- **第二轮打磨（同日，见 decisions.md 第二条 ADR）**：最低系统升至 **macOS 26**（双写与 `Glass.swift` 全删，零 warning）；网格方形卡（1:1、adaptive 150–200）；卡上 hover 圆钮与文件名胶囊删除（右键 / inspector / 新增 ⌘C 三条路径，tooltip 载名称尺寸）；inspector 改 `Form(.grouped)` + `LabeledContent`（名称/尺寸/引擎 + 两个全宽操作行）；**预览切换卡顿修复**——`CGImageSource` 缩略解码取代"解码→重编码 PNG→再解码"，陈旧解码取消、旧图保留到新图就绪；`ModelDescriptor.version` 预留（manifest 已标 v1，更新检查进 backlog）。290 测试全绿。
- **UI 全面回归标准组件（2026-08-10，见 decisions.md 同日）**：主窗口 = 标准 titled 窗口 + unified toolbar（Add / 默认引擎菜单 / Preview / Export）+ 卡片网格 + **`.inspector` 预览侧栏**（before/after 滑块、引擎切换、拷贝/存储/删除）；菜单栏 shelf、状态项、预览浮窗、presence 双开关**整体删除**；Settings 改为标准两 tab（General / Models），Updates 节删除、"Check for Updates…" 回到 app 菜单；珊瑚橙退出 UI，控件染色跟随系统 accent。整窗拖放注册在 `NSWindow` 本身；批量进度走 `navigationSubtitle`；⌫ 删除选中。290 测试全绿，实机验收通过。**待办**：app 图标与（已无 menubar 的）视觉识别重设计；伪本地化复跑一轮排版弹性。

## 历史状态（2026-07-27 深夜）

- 阶段：**v0.1 全部完成、发布链路跑通；v0.2 第一、二批已落地**（磁盘化 + 历史持久化 + 偏好存储 + Settings 窗口；并发闸 + 主窗口批量队列）。PluckKit（VisionEngine/Compositor/ImageLoader/**PluckPipeline**/**PluckQueue**）、`pluck` CLI、PluckApp 菜单栏 + 主窗口、CC0 测试图片集全部落地，**330 测试全绿**，Swift 6 零 warning。
- **v0.2 验收状态（2026-07-28 早）**：解锁后已逐屏看过——Settings 窗口（两组、开关、Clear、离线说明）、主窗口空态（虚线投放区 + ⌘V 提示、Export All 正确隐藏）、主窗口列表态（缩略图 + 尺寸 + hover 出 Copy/Save）、多张时的按整图进度条、失败行（红三角 + "No subject found in this image."）、Export All 全链路（9 张落盘、重名让位成 `Cutout 2.png`…、底栏报 `✓ Exported 9 cutouts.`）。历史持久化早已实测：重启后 cutout 原样回来。**仍需维护者本机确认的只剩一项**：拖出到别的 app——自动化驱不动 macOS 拖放，这条只有人手能验。（开机自启已于 2026-07-28 整条删除，见 decisions.md。）
- **v0.3 模型链路全部落地（2026-07-28）**：PluckKit 新增 `CoreMLEngine`（`.cpuAndGPU` 硬钉，async 加载 + 编译缓存）、`ModelRegistry`（manifest / 下载 / SHA256 / 原子安装 / **断点续传**）与下沉到 Kit 的 `EngineCatalog`；GitHub Release `models-v1` 已发布，`pluck models list` / `models pull` / `--model` 实测全通。**断点续传**用手写 `Range` + `If-Range`（不用 `resumeData`，理由见 decisions.md），本地 `Scripts/serve-models.py` 提供 206/200/416 与 ETag，集成测试真网零依赖；实测 82 MB 资产 pull 到 51 MB `kill -9`，再 pull 从 61% 续起并装成功。**app 侧接线完成**：`Preferences.engineID`（默认 vision）、`EngineProvider`（actor，首次编译只做一次，加载失败回落 Vision + 状态消息）、Settings 新增 Models 一节（引擎 Picker + 每模型 available/downloading/installed 三态，下载与删除全走 ModelRegistry），manifest 由 `Scripts/bundle.sh` 拷进签名 bundle。实测：`pluck fur-01.jpg --model birefnet-lite` 首次 55 秒（含 Core ML 编译）、之后 1.8 秒，未安装时 exit 3。**仍需维护者本机验收**：Settings Models 面板与引擎切换的视觉/交互（自动化驱不动 GUI）。
- **形态改为 Dock 优先（2026-07-29）**：默认 `.regular` —— 有 Dock 图标、启动即开主窗口、点 Dock 图标回主窗口、**拖图到 Dock 图标即处理**（`CFBundleDocumentTypes` + `application(_:open:)`，实测 `open -a Pluck a.jpg b.jpg c.jpg` 三张一次进批量并入库）。菜单栏图标与 shelf 变为可选快捷路径，两个开关在 Settings ▸ General（`Show Pluck in the menu bar` / `Hide the Dock icon`），运行时即时生效，不得同时导致"无处可点"。见 decisions.md 同日与 product-plan §4.3。
- **同批 UI 修正（2026-07-29）**：主窗口底部常驻操作栏（`+ Add` 开 NSOpenPanel / Select All ⇄ Deselect All / Clear / Export N）、顶部 28pt 死白改为 10pt + 滚动内边距 + 顶部渐隐、同 app 内拖拽不再被自己的投放目标接住；shelf 头部收到 10pt 且 Clear 与图标钮同体量；面板圆角四角的方形底修掉（根因：`NSGlassEffectView` 不裁剪 `contentView`，见 decisions.md）；Settings 模型区改为「默认引擎 Picker + 纯管理清单」，体积一律取实际磁盘，History 的 Clear 按钮带体积后缀。
- **本轮验收方式的变化**：本机 `screencapture` 因缺屏幕录制权限一律返回全黑，逐面截图改为进程内 `NSHostingView.cacheDisplay` 渲染（`SurfaceSnapshotTests`，设 `PLUCK_SNAPSHOT_DIR` 落 PNG）。`ImageRenderer` 不可用——它对任何含玻璃的层级返回全透明图。面板圆角改用逐像素断言（`PanelBackdropTests`）。
- 交互现状：状态项本身是拖放目标 → 落下即开 shelf 面板（非激活 borderless NSPanel，网格内占位卡原地变结果卡）；预览面板贴 shelf 旁开、层级在其之上、顶部 44pt 条带可拖、关闭按钮常驻；shelf 底栏 `macwindow` 开主窗口——标准标题栏、一列 batch 行（缩略图 + 文件名 + 尺寸，hover 出 Copy/Save，整行可拖出）、多张时显示按整图计数的进度条、底栏 `Export All…`。
- 打包：`./Scripts/bundle.sh` 产出可运行的 `Pluck.app`（Info.plist / 编译后的 String Catalog / icns / ad-hoc 签名），1.9 MB。
- **发布链路已全程跑通（2026-07-27）**：`./Scripts/release.sh` 一次通过——Developer ID 签名（hardened runtime + timestamp）→ notarytool `Accepted`（提交 `7f7651b9`）→ stapler → 重新打包 → `spctl` 判定 `accepted / source=Notarized Developer ID`。zip 解压到别处二次判定同样通过，`stapler validate` 通过（票据已内嵌，用户首次启动不需要网络），启动 + SIGUSR1 实测存活。产物 `.build/Pluck.zip`，1.9 MB。
- 签名身份：`Developer ID Application: Ruochen Lyu (B4BJ3QY8T2)`；Bundle ID `com.aix4u.pluck`（decisions.md 2026-07-27）；公证 keychain profile 名 `pluck-notary`。
- 待办（v0.1 收尾）：UI 细节打磨（进行中，见下方技术债清单）→ 维护者本机验收 → GitHub Release（tag/正文/附 zip + SHA256）→ Homebrew cask。
- **无阻塞项**。

## 里程碑（2026-07-28 起：单一 1.0 门槛）

> **维护者决定：不到 1.0 不发布。** v0.1/0.2/0.3 的阶段划分作废——它们曾是发布点，现在只是已完成工作的历史编号。以下未完项全部是 1.0 的前置，做完才有第一次公开发布（GitHub Release + Homebrew tap）。

**已完成**（原 v0.1–v0.3 全部范围）：PluckKit 引擎（Vision + CoreML 双引擎）、CLI（--json/exit codes/models pull/断点续传）、菜单栏 shelf + 预览（before/after 滑块）+ 主窗口画廊（多选/导出）、历史持久化、Settings、模型公开发布与按需下载、引擎切换（Clean Cut / Fine Edges）、Liquid Glass 全表面、多语言（en/zh-Hans 实时切换）、签名 + notarize 链路。

**通往 1.0 的未完项**：

1. ~~**Sparkle 自动更新**~~ ✅ 2026-07-29：Sparkle 2.9.4（SPM，只挂 PluckApp，app 目标唯一第三方依赖）。`UpdateController` 把 Sparkle 收在一个四方法协议后面，因此开关联动可单测；`Preferences.checksForUpdates`（默认 true）是唯一真相，启动时单向推进 Sparkle，间隔 86400s；入口两处——状态项右键菜单 About 之下、Settings 新增 Updates 一节（开关 + Check Now + 版本号 + 一句网络披露）。`bundle.sh` 现在嵌 Sparkle.framework（`ditto` + `install_name_tool` 加 rpath，不用 `unsafeFlags`）并接管由内向外的签名顺序，`release.sh` 只把身份传进去；包从 1.9 MB 长到 6.2 MB。**维护者待办（唯一阻塞发布的一步）**：跑 Sparkle 的 `./bin/generate_keys` 生成 EdDSA 密钥对（私钥进 Keychain、务必备份，公钥写 `Packaging/sparkle_public_key.txt` 或 `SPARKLE_PUBLIC_ED_KEY`），然后 `SPARKLE_BIN=... ./Scripts/release.sh` 生成并签 appcast.xml。**公钥缺席时一切照常出包**，只是那个构建没有更新器（decisions.md 2026-07-29）。CI 化 `generate_appcast` 留 TODO——把更新私钥放进 hosted runner 是另一个量级的风险，要单独决定。
2. **Finder Quick Action**——需建 Xcode appex 壳，会触碰签名+公证链路，安排在其他项清空后一次性验证。
3. **skills/pluck/SKILL.md 定稿**——agent 场景的最后一块。
4. **边缘 decontamination**（Compositor 去背景色渗透）——Pixelmator 口碑最好的点。
5. **营销与文档**：发丝 before/after 素材（The magenta test 底稿已有）、README 定稿、官网（可选）。
6. **发布工程**：CI 化 release.sh、GitHub Release（app DMG + CLI 二进制）、Homebrew tap、发 HN + 少数派/V2EX。

Backlog（不阻塞 1.0）：固定结果、全局快捷键唤出 shelf、修饰键拖出选格式（research.md 附录 B）、发布产物启动冒烟检查。


## v0.2 动工前的技术债（2026-07-27，来自 v0.1 实现的上报）

- ~~**端到端管线 API 下沉 PluckKit**~~ ✅ 2026-07-27：`PluckPipeline.run(_:) -> PluckRun`，CLI Runner 与 App PluckService 均降为薄壳（decisions.md 同日）。
- ~~**缩略图/降采样 helper 公开**~~ ✅ 2026-07-27：公开 `Thumbnail.fit/pngData`（按长边）；`ImageBuffers` 维持 internal。
- ~~**String Catalog 在纯 SwiftPM 下不编译**~~ ✅ 2026-07-27：`Scripts/bundle.sh` 跑 xcstringstool 编进 `Contents/Resources/<lang>.lproj`，实测新增 zh-Hans 生效。结论是**不建 Xcode 工程**（decisions.md 同日），Xcode 壳推迟到真正需要它的 Finder 扩展。
- ~~**PluckError 文案硬编码英文**~~ ✅ 2026-07-27：解法不是给 PluckKit 加本地化，而是 App 侧 `PluckFailure` 把 `PluckError.Kind` 映射成自己的 Catalog 文案；库保持机器可读，app 决定怎么说（decisions.md 同日）。
- ~~**历史记录持久化**~~ ✅ 2026-07-27（v0.2 第一批）：最近 20 条默认持久化到 `Application Support/Pluck/History/`，设置可关 + 一键 Clear。做法是把条目**反过来以文件为准**——cutout/original/thumbnail 三个文件一目录，内存只留缩略图字节，拖出用的临时文件与历史文件合并成同一份产物（decisions.md 同日）。**预览面板位置**与**开机自启**随同一份 `UserDefaults` 一起落地，齿轮按钮随之请回。
- ~~**预览面板每次打开都贴回 shelf 旁**~~ ✅ 2026-07-27：面板复用导致每次 `show` 都重新摆位，用户拖走的位置下一次点击就被吃掉。改为记住用户拖过之后的**左上角**（面板按图逐张 resize，从左下往上长，记下边缘会让顶边跳），仍然 clamp 回当前屏幕；`origin(for:keeping:in:)` 抽成纯函数并覆盖测试。
- ~~**临时文件跨 session 堆积**~~ ✅ 2026-07-27：每张 cutout 为了支持拖出会落一份 PNG 到 `<tmp>/Pluck/<uuid>/`，Clear 会删，退出/崩溃不删。改为启动时同步清空整个 `<tmp>/Pluck/`（decisions.md 同日）。
- ~~**齿轮按钮名不副实**~~ ✅ 2026-07-27：`gearshape`／"Settings" 一直打开的是 About 面板，而 v0.1 四项设置（引擎/模型/格式/快捷键）一项都不存在。改标签为 `info.circle`／"About Pluck"，不为凑齐齿轮而临时发明设置项（decisions.md 同日）。
- ~~**菜单栏图标可达性兜底**~~ ✅ 2026-07-27（提前到 v0.1，因为它挡住了我自己的 UI 验收）：`statusAnchor()` 判定图标是否真的够得着（刘海 `auxiliaryTopLeftArea/RightArea`、零宽按钮、找不到所在屏），够不着时 shelf 从可用区顶部中央落下；`applicationShouldHandleReopen` 让"再点一次 app"成为逃生通道；启动 700ms 后若仍不可达则自动开一次 shelf。安置逻辑抽成纯函数 `ShelfPanelController.origin(for:under:in:)` 并覆盖测试。
- ~~**抠图对自身输出不幂等**~~ ✅ 2026-07-27（QA 发现并当场修掉）：结果会写回剪贴板，于是连按两次 ⌘V 抠的是上一次的输出；每过一遍边缘 alpha 再削一点、字节全变，指纹去重因此永远不触发。改为**进引擎前**先拿输入字节比对已有结果的指纹，命中即提升 + 高亮（新 outcome `.superseded`），实测连抠三次仍只有一格。

## 风险与对策

- ~~**BiRefNet_lite → Core ML 转换是最大不确定项**~~ ✅ 2026-07-28 spike 落定（research.md 附录 A.5）：**可行**。fp16 mlpackage 实测 **94 MB**（不是猜的 140 MB），1024² warm 推理 0.59 秒，与 fp32 原模型二值一致率 99.99%。四个坑（deform_conv2d 手写替换 / aten::Int 垫片 / rank-6 重排 / ANE 拒编译）全部有解，复现路径 `Scripts/fetch-models.sh` + `Scripts/convert-birefnet.py`。遗留的实现约束：CoreMLEngine 必须以 `.cpuAndGPU` 加载（ANE 编译不了 deform 的 gather 链），首次加载约 10 秒需要在 UI 上有交代。
- **Vision API 需 macOS 14+**：系统要求写清楚，不做旧系统兼容。
- ~~**VisionEngine 的 `handler.perform` 是同步调用，会阻塞 async 协作线程**~~ ✅ 2026-07-27：`mask(for:)` 去掉 `async`（那件外套只是藏起了它阻塞的是谁），整条管线改在 `PluckQueue` 上跑——一个既限流（宽度 2–4）又换线程（私有并发 `DispatchQueue`）的 actor。批量拖放的内存上限从此由我们定，而不是由用户选了多少张文件决定（decisions.md 同日）。
- **测试图片集**（发丝/毛发/玻璃/多主体/无主体/超大图）在 v0.1 期间攒齐——VisionEngine QA 即用，也是未来双引擎对比基准。
