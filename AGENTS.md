# Pluck — Agent 协作指南

macOS 原生离线抠图（remove background）应用。免费开源，GitHub 分发。
本文件是所有 AI agent（Claude Code / Codex 等）的入口文档。`CLAUDE.md` 是指向本文件的软链接。

## 项目一句话

**Pluck — lift subjects out of photos. Offline, free, open source.**
拖进来、抠出去，照片从不离开这台 Mac。同一引擎暴露为 App、CLI 和 agent skill。

## 文档地图（改动前先读对应文档）

| 文档 | 内容 | 维护规则 |
|---|---|---|
| [docs/product-plan.md](docs/product-plan.md) | 产品定义、卖点、架构设计、里程碑 | 产品/架构决策变更时**必须**同步更新 |
| [docs/research.md](docs/research.md) | 技术方案与竞品调研（2026-07） | 历史参考，只追加不改写 |
| [docs/decisions.md](docs/decisions.md) | 决策记录（ADR，追加式） | 每个不可逆/有争议的决策记一条：背景、选项、结论、理由 |
| [docs/prototypes/](docs/prototypes/) | UI 原型图与讨论结论 | 原型定稿后把结论写进 product-plan |

## 架构（详见 product-plan.md §4）

```
Sources/PluckKit/    核心引擎库，无 UI 依赖 —— 唯一的真相源
Sources/PluckCLI/    命令行（swift-argument-parser），PluckKit 薄壳
Sources/PluckApp/    SwiftUI app（菜单栏 + 主窗口 + 结果浮层），PluckKit 薄壳
Extensions/          Finder Quick Action
skills/pluck/        agent skill（SKILL.md）
models/manifest.json 可下载模型清单
```

核心原则：

1. **PluckKit 是唯一引擎**。App/CLI/扩展不得各自实现抠图逻辑，只能调用 PluckKit。
2. **默认零网络**。仅有的网络行为：用户显式触发的模型下载、可关闭的 Sparkle 更新检查。任何新增网络请求都是重大决策，需记入 decisions.md。
3. **默认引擎是 Apple Vision**（`VNGenerateForegroundInstanceMaskRequest`，macOS 14+，零体积）。高质量模型（BiRefNet_lite 等，必须 MIT/Apache license）按需下载，不进 bundle。
4. **模型扩展 = manifest 加记录**，不改代码。新模型必须核查 license（RMBG 系 CC BY-NC 已明确排除）。

## 工程约定

- 语言：Swift 6，SwiftUI；最低系统 macOS 14。
- 构建：SwiftPM 为主（`swift build` / `swift test`）；App 壳与扩展用 Xcode 工程（进入 v0.2 后建立）。
- CLI 设计面向 agent：`--json` 结构化输出、语义化 exit code（0 成功 / 2 未检测到主体 / 3 模型缺失）、无 TTY 不输出进度、绝不弹 GUI。
- 提交信息用英文，正文说明 why；一个 PR/提交是一个自洽可评审的单位。
- 注释密度低：只写代码本身表达不了的约束。
- 面向用户的文案：英文为主（README、app 内文案），中文文档放 docs/。

## 当前状态

- 阶段：**立项 / v0.1 之前**。代码尚未开始，正在做 UI 原型讨论。
- 下一步：原型定稿 → 搭 SwiftPM 骨架 → PluckKit VisionEngine → CLI → 菜单栏 MVP。
