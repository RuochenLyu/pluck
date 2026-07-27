# Roadmap 与当前状态

> 本文件是唯一的进度真相源：阶段推进、里程碑范围变化时更新这里。
> 产品定义与架构见 [product-plan.md](product-plan.md)，决策记录见 [decisions.md](decisions.md)。

## 当前状态（2026-07-27 深夜）

- 阶段：**v0.1 功能代码完成并过完三轮用户实测反馈**（⌘V 入口 → 拖到图标即入口的 shelf 面板重做 → 浮层层级/摆位/拖动/关闭按钮）。PluckKit（VisionEngine/Compositor/ImageLoader/**PluckPipeline**）、`pluck` CLI、PluckApp 菜单栏 MVP、CC0 测试图片集全部落地，**92 测试全绿**，Swift 6 零 warning。
- 交互现状：状态项本身是拖放目标 → 落下即开 shelf 面板（非激活 borderless NSPanel，网格内占位卡原地变结果卡）；预览面板贴 shelf 旁开、层级在其之上、顶部 44pt 条带可拖、关闭按钮常驻。
- 打包：`./Scripts/bundle.sh` 产出可运行的 `Pluck.app`（Info.plist / 编译后的 String Catalog / icns / ad-hoc 签名），1.9 MB。
- 待办（v0.1 收尾）：剩余 UI 细节打磨归到最后一期统一处理 → Developer ID 签名 + notarization + GitHub Release + Homebrew tap。
- 发布链路：`./Scripts/release.sh` 已就位（Developer ID 签名 → notarytool → stapler → 重新打包 → spctl 判定）。Developer Program 会员**已确认有效**（Admin，Certificates/Identifiers/Profiles 可用）。
- **阻塞在用户**：① developer.apple.com/account 接受更新后的 PLA（Xcode 建证书报 "Unable to process request – PLA Update available"，这是唯一原因）；② 接受后回 Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates… ▸ + ▸ Developer ID Application；③ `xcrun notarytool store-credentials pluck-notary`（需 App-Specific Password）。三步做完 `release.sh` 即可跑通，无其他阻塞项。
- Bundle ID 终定为 `com.aix4u.pluck`（用现有域名 `aix4u.com`，不为本 app 单独注册域名；decisions.md 2026-07-27）。
- Developer ID Application 证书**已就位**：`Developer ID Application: Ruochen Lyu (B4BJ3QY8T2)`，Team ID `B4BJ3QY8T2`。

## 里程碑

- **v0.1（MVP，目标 1–2 周业余时间）**：PluckKit(VisionEngine) + CLI + 菜单栏拖放 + popover ⌘V 剪贴板闭环 + 结果预览滑块。签名 + notarize + GitHub Release + tap。
- **v0.2**：主窗口批量队列、结果浮层、Finder Quick Action、Sparkle。
- **v0.3**：CoreMLEngine + BiRefNet_lite 转换与按需下载、对比滑块、SKILL.md 定稿。
- **v1.0**：边缘 decontamination 打磨、发丝 before/after 营销图、README/官网、发 HN + 少数派/V2EX。

## v0.2 动工前的技术债（2026-07-27，来自 v0.1 实现的上报）

- ~~**端到端管线 API 下沉 PluckKit**~~ ✅ 2026-07-27：`PluckPipeline.run(_:) -> PluckRun`，CLI Runner 与 App PluckService 均降为薄壳（decisions.md 同日）。
- ~~**缩略图/降采样 helper 公开**~~ ✅ 2026-07-27：公开 `Thumbnail.fit/pngData`（按长边）；`ImageBuffers` 维持 internal。
- ~~**String Catalog 在纯 SwiftPM 下不编译**~~ ✅ 2026-07-27：`Scripts/bundle.sh` 跑 xcstringstool 编进 `Contents/Resources/<lang>.lproj`，实测新增 zh-Hans 生效。结论是**不建 Xcode 工程**（decisions.md 同日），Xcode 壳推迟到真正需要它的 Finder 扩展。
- **PluckError 文案硬编码英文**：App 要在 UI 展示错误文本（v0.2 浮层）前，需给 PluckKit 一条可本地化路径。
- **历史记录持久化**（v0.1 反馈）：当前 session 内存 12 条；v0.2 改为默认持久化最近 20 条到 Application Support（本地磁盘不违背"不上网"承诺），设置可关 + 一键 Clear。
- **菜单栏图标可达性兜底**：刘海机型 + 菜单栏拥挤时状态项会被藏进刘海下，app 无 Dock 图标无窗口即完全不可达（2026-07-27 实测发生）。v0.2 需要兜底：二次启动检测已有实例时强制弹 popover / 引导。全局快捷键已移除，目前唯一的逃生通道是 SIGUSR1（脚本级，普通用户用不上）。

## 风险与对策

- **BiRefNet_lite → Core ML 转换是最大不确定项**（自转，无现成 mlpackage）：属 v0.3 范围但建议骨架搭好后尽早做 time-boxed spike（一两天）验证可行性并拿到真实体积数字；spike 之前"140 MB"不得写进面向用户的文案。不阻塞 v0.1。
- **Vision API 需 macOS 14+**：系统要求写清楚，不做旧系统兼容。
- **VisionEngine 的 `handler.perform` 是同步调用，会阻塞 async 协作线程**：单张场景（v0.1）可接受；v0.2 主窗口批量队列动工前需决定是否移到专用 executor。
- **测试图片集**（发丝/毛发/玻璃/多主体/无主体/超大图）在 v0.1 期间攒齐——VisionEngine QA 即用，也是未来双引擎对比基准。
