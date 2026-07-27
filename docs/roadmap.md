# Roadmap 与当前状态

> 本文件是唯一的进度真相源：阶段推进、里程碑范围变化时更新这里。
> 产品定义与架构见 [product-plan.md](product-plan.md)，决策记录见 [decisions.md](decisions.md)。

## 当前状态（2026-07-27 晚）

- 阶段：**v0.1 功能代码完成**，已过一轮用户上手反馈迭代（⌘V 入口 / popover 重排 / 预览滑块）。PluckKit（VisionEngine/Compositor/ImageLoader）、`pluck` CLI、PluckApp 菜单栏 MVP、CC0 测试图片集全部落地，60 测试全绿，Swift 6 零 warning。
- 待办（v0.1 收尾）：GUI 人工验证（拖放到图标 / popover 点击与布局 / popover 内 ⌘V / Recent 拖出 / 预览滑块）→ Developer ID 签名 + notarization + GitHub Release + Homebrew tap。

## 里程碑

- **v0.1（MVP，目标 1–2 周业余时间）**：PluckKit(VisionEngine) + CLI + 菜单栏拖放 + popover ⌘V 剪贴板闭环 + 结果预览滑块。签名 + notarize + GitHub Release + tap。
- **v0.2**：主窗口批量队列、结果浮层、Finder Quick Action、Sparkle。
- **v0.3**：CoreMLEngine + BiRefNet_lite 转换与按需下载、对比滑块、SKILL.md 定稿。
- **v1.0**：边缘 decontamination 打磨、发丝 before/after 营销图、README/官网、发 HN + 少数派/V2EX。

## v0.2 动工前的技术债（2026-07-27，来自 v0.1 实现的上报）

- **端到端管线 API 下沉 PluckKit**：load → mask → compose → encode 目前在 CLI Runner 和 App PluckService 各有一份，Finder 扩展会是第三份——v0.2 第一个单元先做这个下沉。
- **缩略图/降采样 helper 公开**：`ImageBuffers` 是 internal，App 自己重写了降采样；随管线下沉一并公开。
- **String Catalog 在纯 SwiftPM 下不编译**（只 copy 不跑 xcstringstool）：英文 fallback 正确，但新增语言会被静默忽略——v0.2 建 Xcode app 壳时解决，多语言发布依赖此项。
- **PluckError 文案硬编码英文**：App 要在 UI 展示错误文本（v0.2 浮层）前，需给 PluckKit 一条可本地化路径。
- **历史记录持久化**（v0.1 反馈）：当前 session 内存 12 条；v0.2 改为默认持久化最近 20 条到 Application Support（本地磁盘不违背"不上网"承诺），设置可关 + 一键 Clear。
- **菜单栏图标可达性兜底**：刘海机型 + 菜单栏拥挤时状态项会被藏进刘海下，app 无 Dock 图标无窗口即完全不可达（2026-07-27 实测发生）。v0.2 需要兜底：二次启动检测已有实例时强制弹 popover / 引导。全局快捷键已移除，目前唯一的逃生通道是 SIGUSR1（脚本级，普通用户用不上）。

## 风险与对策

- **BiRefNet_lite → Core ML 转换是最大不确定项**（自转，无现成 mlpackage）：属 v0.3 范围但建议骨架搭好后尽早做 time-boxed spike（一两天）验证可行性并拿到真实体积数字；spike 之前"140 MB"不得写进面向用户的文案。不阻塞 v0.1。
- **Vision API 需 macOS 14+**：系统要求写清楚，不做旧系统兼容。
- **VisionEngine 的 `handler.perform` 是同步调用，会阻塞 async 协作线程**：单张场景（v0.1）可接受；v0.2 主窗口批量队列动工前需决定是否移到专用 executor。
- **测试图片集**（发丝/毛发/玻璃/多主体/无主体/超大图）在 v0.1 期间攒齐——VisionEngine QA 即用，也是未来双引擎对比基准。
