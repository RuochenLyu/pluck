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
