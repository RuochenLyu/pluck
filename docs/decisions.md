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
