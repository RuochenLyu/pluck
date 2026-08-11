# Pluck

**把主体从照片里拎出来。离线、免费、开源。**

[English](README.md) · 简体中文

Pluck 是一个原生 macOS 应用（附带 CLI），完全在设备端移除图片背景。
你的照片从不离开你的 Mac——没有账号、没有上传、没有订阅、没有水印。

## 安装

- **直接下载**：从[最新 Release](https://github.com/RuochenLyu/pluck/releases/latest) 下载 `Pluck.zip`，解压后拖入「应用程序」。已签名并公证。
- **Homebrew**：`brew tap RuochenLyu/pluck && brew install --cask pluck`（应用）· `brew install RuochenLyu/pluck/pluck`（命令行）
- 需要 macOS 26+（Apple 芯片）。

## 为什么又做一个抠图工具？

- **默认离线。** 苹果设备端 Vision 框架；可选的高质量 BiRefNet 模型（MIT 协议，
  [发布在这里](https://github.com/RuochenLyu/pluck/releases/tag/models-v1)）按需下载，
  并对照钉死的 SHA256 摘要校验。可审计——代码全在这里。
- **引擎会有用地不同意。** Vision 即时出图、对"没有主体"诚实说不；BiRefNet 利落边
  能救回线稿、还会穿进翻拍的画里抠出画中主体（Vision 则把带框的画整体抠出）；柔细边
  把玻璃抠成真正的透明。这些是实测结论，不是营销词——见[审计记录](docs/research.md)。
- **原生且零配置。** 一个标准窗口：拖入图片（或直接 ⌘V 粘贴剪贴板），before/after
  并排对比，逐图切换引擎，批量导出。网格/列表双视图，历史跨启动保留。
- **为 AI agent 而生。** 同一引擎以 `pluck` CLI 发布：`--json` NDJSON 输出、语义化
  exit code、无 GUI、不假设 TTY。
- **免费，永远免费。** 没有"高清要付费"，没有按周订阅。

## 架构

`PluckKit`（Swift 库，唯一引擎）→ 薄壳：SwiftUI 应用与 `pluck` CLI。Vision 内建即用；
BiRefNet 变体在显式执行 `pluck models pull <id>`（或在设置里点击下载）后经 Core ML 运行。
模型更新随应用更新到达，与本地安装收据比对——检查不产生任何网络请求。需要 macOS 26+。

```bash
swift build            # 库 + CLI
swift test             # 全部测试，无需网络
./Scripts/bundle.sh    # 在 .build/ 产出可运行的 Pluck.app
```

## 什么会联网

你的图片永远不会。抠图完全在这台 Mac 上进行，应用里没有账号、没有遥测、没有任何上传路径。
有两件事会联网，都列在这里——隐私承诺的价值恰恰取决于例外是否交代清楚：

| 什么 | 何时 | 如何关闭 |
|---|---|---|
| **模型下载** | 仅当你在 设置 ▸ 模型 点击下载，或运行 `pluck models pull` 时。从本仓库的 GitHub Releases 拉取 BiRefNet 包，并对照 [`models/manifest.json`](models/manifest.json) 钉死的 SHA256 校验。 | 你不要求就不会发生。 |
| **更新检查** | 应用每天向 GitHub 询问一次是否有新版本。不会发送任何关于你或你图片的信息。更新以 EdDSA 签名并在安装前验证（[Sparkle](https://sparkle-project.org)）。 | 设置 ▸ 通用 ▸ *自动检查更新*。关掉后 Pluck 不再主动发起任何请求。 |

`pluck` CLI 从不检查更新——它唯一可能的网络调用是显式的 `models pull`。

## 与 AI agent 一起用

Pluck 在 [`skills/pluck/`](skills/pluck/SKILL.md) 内置了 agent skill。复制或软链接安装：

```bash
ln -s "$PWD/skills/pluck" ~/.claude/skills/pluck    # 或: cp -r skills/pluck ~/.claude/skills/
```

之后 agent 使用的就是你会用的同一个 CLI：

```bash
pluck shots/*.jpg -o cutouts/ --json     # stdout 上每图一行 NDJSON
pluck photo.jpg --model birefnet-lite-matting -o cut.png
```

[SKILL.md](skills/pluck/SKILL.md) 完整记录了 `--json` 契约、`error` slug 与 exit code
（0 成功 · 1 错误 · 2 未检测到主体 · 3 模型问题）。

## 文档

- [产品方案](docs/product-plan.md) · [路线图](docs/roadmap.md) · [调研](docs/research.md) · [决策记录](docs/decisions.md)
- Agent 从 [AGENTS.md](AGENTS.md) 开始

## 许可证

MIT。打包的模型转换产物保留其上游 MIT 许可与署名——见每个
[模型资产](https://github.com/RuochenLyu/pluck/releases/tag/models-v1)内附的 NOTICE。
