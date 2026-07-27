# Roadmap 与当前状态

> 本文件是唯一的进度真相源：阶段推进、里程碑范围变化时更新这里。
> 产品定义与架构见 [product-plan.md](product-plan.md)，决策记录见 [decisions.md](decisions.md)。

## 当前状态（2026-07-27）

- 阶段：**v0.1 开发前夜**。UI 原型已定稿（[prototypes/](prototypes/)，结论见 [product-plan.md](product-plan.md) §4.7），代码尚未开始。
- 下一步：搭 SwiftPM 骨架 → PluckKit VisionEngine + 测试图片集 → CLI → 菜单栏 MVP。

## 里程碑

- **v0.1（MVP，目标 1–2 周业余时间）**：PluckKit(VisionEngine) + CLI + 菜单栏拖放 + 剪贴板快捷键。签名 + notarize + GitHub Release + tap。
- **v0.2**：主窗口批量队列、结果浮层、Finder Quick Action、Sparkle。
- **v0.3**：CoreMLEngine + BiRefNet_lite 转换与按需下载、对比滑块、SKILL.md 定稿。
- **v1.0**：边缘 decontamination 打磨、发丝 before/after 营销图、README/官网、发 HN + 少数派/V2EX。

## 风险与对策

- **BiRefNet_lite → Core ML 转换是最大不确定项**（自转，无现成 mlpackage）：属 v0.3 范围但建议骨架搭好后尽早做 time-boxed spike（一两天）验证可行性并拿到真实体积数字；spike 之前"140 MB"不得写进面向用户的文案。不阻塞 v0.1。
- **Vision API 需 macOS 14+**：系统要求写清楚，不做旧系统兼容。
- **VisionEngine 的 `handler.perform` 是同步调用，会阻塞 async 协作线程**：单张场景（v0.1）可接受；v0.2 主窗口批量队列动工前需决定是否移到专用 executor。
- **测试图片集**（发丝/毛发/玻璃/多主体/无主体/超大图）在 v0.1 期间攒齐——VisionEngine QA 即用，也是未来双引擎对比基准。
