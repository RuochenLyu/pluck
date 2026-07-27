# Roadmap 与当前状态

> 本文件是唯一的进度真相源：阶段推进、里程碑范围变化时更新这里。
> 产品定义与架构见 [product-plan.md](product-plan.md)，决策记录见 [decisions.md](decisions.md)。

## 当前状态（2026-07-27 深夜）

- 阶段：**v0.1 功能代码完成并过完三轮用户实测反馈**（⌘V 入口 → 拖到图标即入口的 shelf 面板重做 → 浮层层级/摆位/拖动/关闭按钮）。PluckKit（VisionEngine/Compositor/ImageLoader/**PluckPipeline**）、`pluck` CLI、PluckApp 菜单栏 MVP、CC0 测试图片集全部落地，**92 测试全绿**，Swift 6 零 warning。
- 交互现状：状态项本身是拖放目标 → 落下即开 shelf 面板（非激活 borderless NSPanel，网格内占位卡原地变结果卡）；预览面板贴 shelf 旁开、层级在其之上、顶部 44pt 条带可拖、关闭按钮常驻。
- 打包：`./Scripts/bundle.sh` 产出可运行的 `Pluck.app`（Info.plist / 编译后的 String Catalog / icns / ad-hoc 签名），1.9 MB。
- **发布链路已全程跑通（2026-07-27）**：`./Scripts/release.sh` 一次通过——Developer ID 签名（hardened runtime + timestamp）→ notarytool `Accepted`（提交 `7f7651b9`）→ stapler → 重新打包 → `spctl` 判定 `accepted / source=Notarized Developer ID`。zip 解压到别处二次判定同样通过，`stapler validate` 通过（票据已内嵌，用户首次启动不需要网络），启动 + SIGUSR1 实测存活。产物 `.build/Pluck.zip`，1.9 MB。
- 签名身份：`Developer ID Application: Ruochen Lyu (B4BJ3QY8T2)`；Bundle ID `com.aix4u.pluck`（decisions.md 2026-07-27）；公证 keychain profile 名 `pluck-notary`。
- 待办（v0.1 收尾）：UI 细节打磨（进行中，见下方技术债清单）→ 维护者本机验收 → GitHub Release（tag/正文/附 zip + SHA256）→ Homebrew cask。
- **无阻塞项**。

## 里程碑

- **v0.1（MVP，目标 1–2 周业余时间）**：PluckKit(VisionEngine) + CLI + 菜单栏拖放 + popover ⌘V 剪贴板闭环 + 结果预览滑块。签名 + notarize + GitHub Release + tap。
- **v0.2**：主窗口批量队列、结果浮层、Finder Quick Action、Sparkle。
- **v0.3**：CoreMLEngine + BiRefNet_lite 转换与按需下载、对比滑块、SKILL.md 定稿。
- **v1.0**：边缘 decontamination 打磨、发丝 before/after 营销图、README/官网、发 HN + 少数派/V2EX。

## v0.2 动工前的技术债（2026-07-27，来自 v0.1 实现的上报）

- ~~**端到端管线 API 下沉 PluckKit**~~ ✅ 2026-07-27：`PluckPipeline.run(_:) -> PluckRun`，CLI Runner 与 App PluckService 均降为薄壳（decisions.md 同日）。
- ~~**缩略图/降采样 helper 公开**~~ ✅ 2026-07-27：公开 `Thumbnail.fit/pngData`（按长边）；`ImageBuffers` 维持 internal。
- ~~**String Catalog 在纯 SwiftPM 下不编译**~~ ✅ 2026-07-27：`Scripts/bundle.sh` 跑 xcstringstool 编进 `Contents/Resources/<lang>.lproj`，实测新增 zh-Hans 生效。结论是**不建 Xcode 工程**（decisions.md 同日），Xcode 壳推迟到真正需要它的 Finder 扩展。
- ~~**PluckError 文案硬编码英文**~~ ✅ 2026-07-27：解法不是给 PluckKit 加本地化，而是 App 侧 `PluckFailure` 把 `PluckError.Kind` 映射成自己的 Catalog 文案；库保持机器可读，app 决定怎么说（decisions.md 同日）。
- **历史记录持久化**（v0.1 反馈）：当前 session 内存 12 条；v0.2 改为默认持久化最近 20 条到 Application Support（本地磁盘不违背"不上网"承诺），设置可关 + 一键 Clear。**预览面板位置**（当前只活到进程结束）和**开机自启**一并挂在这条下面——三者都要落到同一份偏好存储上，v0.2 有第一个真正的 Settings 界面时一起做。
- ~~**预览面板每次打开都贴回 shelf 旁**~~ ✅ 2026-07-27：面板复用导致每次 `show` 都重新摆位，用户拖走的位置下一次点击就被吃掉。改为记住用户拖过之后的**左上角**（面板按图逐张 resize，从左下往上长，记下边缘会让顶边跳），仍然 clamp 回当前屏幕；`origin(for:keeping:in:)` 抽成纯函数并覆盖测试。
- ~~**齿轮按钮名不副实**~~ ✅ 2026-07-27：`gearshape`／"Settings" 一直打开的是 About 面板，而 v0.1 四项设置（引擎/模型/格式/快捷键）一项都不存在。改标签为 `info.circle`／"About Pluck"，不为凑齐齿轮而临时发明设置项（decisions.md 同日）。
- ~~**菜单栏图标可达性兜底**~~ ✅ 2026-07-27（提前到 v0.1，因为它挡住了我自己的 UI 验收）：`statusAnchor()` 判定图标是否真的够得着（刘海 `auxiliaryTopLeftArea/RightArea`、零宽按钮、找不到所在屏），够不着时 shelf 从可用区顶部中央落下；`applicationShouldHandleReopen` 让"再点一次 app"成为逃生通道；启动 700ms 后若仍不可达则自动开一次 shelf。安置逻辑抽成纯函数 `ShelfPanelController.origin(for:under:in:)` 并覆盖测试。
- ~~**抠图对自身输出不幂等**~~ ✅ 2026-07-27（QA 发现并当场修掉）：结果会写回剪贴板，于是连按两次 ⌘V 抠的是上一次的输出；每过一遍边缘 alpha 再削一点、字节全变，指纹去重因此永远不触发。改为**进引擎前**先拿输入字节比对已有结果的指纹，命中即提升 + 高亮（新 outcome `.superseded`），实测连抠三次仍只有一格。

## 风险与对策

- **BiRefNet_lite → Core ML 转换是最大不确定项**（自转，无现成 mlpackage）：属 v0.3 范围但建议骨架搭好后尽早做 time-boxed spike（一两天）验证可行性并拿到真实体积数字；spike 之前"140 MB"不得写进面向用户的文案。不阻塞 v0.1。
- **Vision API 需 macOS 14+**：系统要求写清楚，不做旧系统兼容。
- **VisionEngine 的 `handler.perform` 是同步调用，会阻塞 async 协作线程**：单张场景（v0.1）可接受；v0.2 主窗口批量队列动工前需决定是否移到专用 executor。
- **测试图片集**（发丝/毛发/玻璃/多主体/无主体/超大图）在 v0.1 期间攒齐——VisionEngine QA 即用，也是未来双引擎对比基准。
