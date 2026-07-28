# macOS 原生 Remove BG 应用 — 技术方案与竞品调研

> 调研日期：2026-07-27。由两个并行调研 agent 完成（技术方案 / 竞品），本文为整合版。

## 一、结论（TL;DR）

**推荐技术架构：双层方案，零模型打包。**

```
默认路径（0 体积，覆盖 90%+ 场景）
  └─ Apple Vision: VNGenerateForegroundInstanceMaskRequest (macOS 14+)
     系统自带模型，与 Finder「移除背景」/ Photos 提取主体同源

可选增强路径（按需下载，~50–250MB）
  └─ Core ML 高质量模型（用户主动开启「高质量模式」时才下载）
     首选 BiRefNet_lite（MIT）或 InSPyReNet（MIT），自行转 Core ML
     存放于 ~/Library/Application Support，不进 app bundle
```

**产品定位：** 系统自带 Quick Action 已经"能抠图"，所以价值不在"能抠"，而在——完全离线隐私、批量处理、菜单栏/Finder/剪贴板全链路集成、比系统更好的发丝边缘（可选模型）、原生 SwiftUI 质感。目前市场上没有产品同时做到这五点，开源侧最接近的 RemoveThatBG 热度很低，空档真实存在。

---

## 二、技术方案

### 2.1 Apple 系统内置能力（主路径）

**VNGenerateForegroundInstanceMaskRequest**（macOS 14 Sonoma+ / iOS 17+）
- 就是 Finder 右键「移除背景」、Preview、Photos「提取主体」背后的同一套模型，公开 API，可直接复用。
- Class-agnostic：人、宠物、物体、食物均可，不限于人像。
- 用法：请求 → `result.allInstances` → `generateMaskedImage(...)` 直接得抠图，或 `generateScaledMaskForImage(...)` 得高分辨率 mask 自行合成。
- 参考实现：[stroniarz/remove-bg](https://github.com/stroniarz/remove-bg)（MIT，~70 行 Swift CLI，边界情况处理可直接借鉴）。

已知局限（需在工程中处理）：
- 不支持模拟器/纯 CPU（依赖 ANE），报 `com.apple.Vision Code=9`；
- 多主体合并为一张 mask，无实例级选择；
- 超大图（>50MP）可能内存溢出，需先降采样；
- 找不到前景时返回空 mask；
- 杂乱背景下发丝边缘偶有光晕（halo），但对产品图/头像/mockup 已"good enough"。

相关 API：
- `VNGeneratePersonSegmentationRequest`（iOS 15+）：仅人像，更快更轻，适合人像专用场景；
- `VNGeneratePersonInstanceMaskRequest`：多人各自独立 mask；
- VisionKit `ImageAnalysisInteraction`：系统同款"长按提取主体"UI，定制性差，做批处理工具用低层 Vision 更合适；
- WWDC 2026 新增 **tap-to-segment API**（点哪抠哪），系统版本要求高，作为未来增强，不做 baseline。macOS 15/26 本身无新分割 API。

### 2.2 可选高质量模型（增强路径）

| 模型 | 体积 | License | 评价 |
|---|---|---|---|
| **BiRefNet_lite** | 44.4M 参数（明显小于 full 版） | **MIT** ✅ | 精度接近 full BiRefNet，性价比最高候选 |
| **InSPyReNet** | ~367MB (.pth) | **MIT** ✅ | 报告称优于 BRIA/U²Net/IS-Net，宽图处理有已知 bug 需验证 |
| U²-Net-p | ~4.5MB | Apache-2.0 ✅ | 极小极快，质量中等 |
| IS-Net (DIS) | ~176MB | Apache-2.0 ✅ | 质量优于 U²Net |
| MODNet | ~26MB | Apache-2.0 ✅ | 仅人像 |
| BiRefNet (full) | 490MB (fp16) | MIT ✅ | 口碑最强但太大 |
| RMBG-1.4 | ~44MB | OpenRAIL-M ⚠️ | 条款需评估 |
| **RMBG-2.0** | 233MB (INT8 Core ML) | **CC BY-NC 4.0** ❌ | 非商用条款，对开源分发是法律隐患，**避开** |

要点：
- **License 红线**：BRIA 系（RMBG）非商用条款即使对免费 app 也有解释风险，选 MIT/Apache 的 BiRefNet_lite / InSPyReNet 更干净。
- **Core ML 转换**：BiRefNet 架构已有社区转换先例（[VincentGOURBIN/RMBG-2-CoreML](https://huggingface.co/VincentGOURBIN/RMBG-2-CoreML)，INT8 量化 233MB + Swift 包），BiRefNet_lite（MIT 权重）走同样 coremltools 流程自行转换，工作量中等，目前无现成公开 mlpackage。
- **按需下载**：模型不打包，首次开启高质量模式时下载，下载前明确标注模型来源与 license。

### 2.3 可借鉴的开源实现

| 项目 | 方案 | 借鉴点 |
|---|---|---|
| [stroniarz/remove-bg](https://github.com/stroniarz/remove-bg) | Vision API CLI | 完整流程 + 边界情况处理 |
| [Ezaldeen99/BackgroundRemoval](https://github.com/Ezaldeen99/BackgroundRemoval) | Swift + U²Net Core ML | Core ML 输入输出预处理 |
| [tbchen/BackgroundRemovalWithCoreMLSample](https://github.com/tbchen/BackgroundRemovalWithCoreMLSample) | Core ML + Core Image | mask 的 alpha 合成细节 |
| [pietrosaveri/RemoveThatBG](https://github.com/pietrosaveri/RemoveThatBG) | SwiftUI 菜单栏 + rembg | **最接近的同类项目**，立项前应试用并读 issues |

macOS 原生开源抠图项目普遍只有个位数到几十 star——细分空白，也是机会。

---

## 三、竞品格局

### 3.1 主要对标

- **系统自带**（免费）：Finder Quick Action / Shortcuts「Remove Background」。弱点：单张为主、Shortcuts 有空结果 bug、无批量 UI、无导出选项。→ 我们的基准线，不是终点。
- **Pixelmator Pro / Photomator**（Apple 收购，买断/订阅）：自研 ML，Hide Background（非破坏矢量蒙版）+ 色彩去污染（decontaminate）是质量标杆。弱点：藏在专业修图软件里，轻量用户杀鸡用牛刀。
- **remove.bg**（credit 制：$9/月 40 credits 起，$100/200 credits 按需）：发丝质量行业标杆。弱点：预览高清、下载 625×400 低清逼付费的 bait-and-switch，被广泛吐槽；需上传、按张计费。
- **Mac App Store 小工具红海**：普遍订阅陷阱（$4.99/月甚至按周订阅）、低清限流、窗口不可缩放、崩溃、隐私政策含糊。唯一被表扬的是"一次性付费"的 PNG Maker（"refreshing"）。
- **Snapclear.app**：主打"100% 离线、绝不上传"，隐私叙事值得借鉴。
- **开源**：rembg（MIT，事实标准引擎，无原生 GUI）；GUI 套壳普遍是 Flask+浏览器，无原生质感；RemoveThatBG 是唯一 SwiftUI 原生方案但热度低。

### 3.2 用户痛点（评论区/Reddit/论坛汇总）

1. 预览诱导付费（remove.bg 系通病）
2. 订阅疲劳——"一次性/免费"被主动表扬
3. 隐私/上传顾虑——含人脸、证件、商业图的用户是硬需求
4. **发丝/半透明边缘差**——所有产品评论区最一致的抱怨
5. 批量处理弱——系统 Shortcuts 要手拼 Repeat with Each
6. UI 简陋、窗口不可缩放、崩溃

**未被满足的组合需求：完全离线 + 免费开源 + 原生 UI + 批量 + 边缘质量不输 remove.bg。目前无人同时做到。**

### 3.3 值得抄的交互模式

1. **菜单栏常驻 + 拖拽即处理**（RemoveThatBG / CleanShot X 范式）
2. **Finder Quick Action / 右键扩展**——用户心智已被系统教育好，注册同一位置
3. **CleanShot X 式处理完浮层**：拖到其它 App / 复制剪贴板 / 存文件夹，多去向、不强制保存对话框
4. **剪贴板闭环**：复制图 → 全局快捷键 → 直接粘贴到 Keynote/聊天，中间不落盘
5. **零配置默认 + 设置里留专业出口**（默认秒出，可切高质量模型）
6. **批量拖入 + 进度可视化**——App Store 小工具普遍缺失的最大机会点

### 3.4 差异化定位建议

1. 第一卖点：**"你的照片从不离开这台 Mac"**——开源代码可审计，为隐私承诺背书
2. 深挖系统能力的薄弱处：批量、模型可选、双入口（菜单栏 + Finder）
3. 把**发丝质量**当核心 KPI——最一致的痛点，也最容易用 before/after 对比图做营销
4. 原生 SwiftUI，拒绝套壳网页观感——这是开源方案普遍输给付费产品的地方
5. 立项前试用 RemoveThatBG、读其 issues，确认增量差异化（批量 UI / Finder 集成深度 / onboarding）

---

## 四、来源

技术：[VNGenerateForegroundInstanceMaskRequest 文档](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest) · [WWDC23 Lift subjects](https://wwdcnotes.com/documentation/wwdc23-10176-lift-subjects-from-images-in-your-app/) · [WWDC26 image understanding](https://developer.apple.com/videos/play/wwdc2026/237/) · [RMBG-2.0 license](https://huggingface.co/briaai/RMBG-2.0) · [RMBG-2-CoreML](https://huggingface.co/VincentGOURBIN/RMBG-2-CoreML) · [BiRefNet_lite](https://huggingface.co/ZhengPeng7/BiRefNet_lite) · [InSPyReNet](https://github.com/plemeri/InSPyReNet) · [Create with Swift 教程](https://www.createwithswift.com/removing-image-background-using-the-vision-framework/)

竞品：[rembg](https://github.com/danielgatis/rembg) · [RemoveThatBG](https://github.com/pietrosaveri/RemoveThatBG) · [snapclear.app](https://www.snapclear.app/) · [remove.bg 定价](https://www.softwaresuggest.com/remove-bg) · [Pixelmator AI 抠图](https://www.macrumors.com/2024/05/23/pixelmator-ai-background-removal-tool/) · [macOS 系统抠图](https://www.macrumors.com/how-to/remove-background-from-image-macos/)

---

## 五、UI/交互设计调研（2026-07-27 追加，第二轮原型前）

> 由四个并行调研 agent 完成：shelf 类工具交互 / Liquid Glass 规范 / 单功能小工具气质 / 抠图直接竞品。

### 5.1 Shelf 类工具（Dropover / Dropzone / Yoink / FilePane）

- **爽感核心是零位移成本**：Dropover 摇动手势在光标当前位置召唤 shelf（Gruber："It feels like you're saying 'Give me a shelf right here'"），优于 Yoink 固定屏幕边缘的形态。对 Pluck 的启示：结果浮层应出现在用户松手位置附近、立刻可拖走。
- **该品类 2026 的竞争焦点就是 Liquid Glass 适配**：Dropzone 5 "ground up 重设计支持 Liquid Glass"；Dropover 刚做了轻玻璃+柔圆角刷新；新玩家 Dockside、FlowShelf 直接以 "floating glass shelf" 为卖点。玻璃材质已是品类标配而非可选项。
- Dropzone 的"目的地网格"复杂度不适合 Pluck——我们动作固定（抠图），应保持零配置。
- 来源：[Daring Fireball 评 Dropover](https://daringfireball.net/linked/2026/05/15/dropover) · [Dropzone 5 发布](https://aptonic.com/blog/dropzone-5-released) · [Macworld 评 Yoink](https://www.macworld.com/article/620102/yoink-review-mac-gems.html)

### 5.2 Liquid Glass 规范要点（macOS 26 Tahoe）

1. **内容/功能分层**：抠图结果和棋盘格属内容层，不加玻璃；玻璃只用于浮层容器、按钮、工具栏等功能层。
2. **自定义强调色（珊瑚橙）被 HIG 支持**，但只 tint 一个主操作（`.glassProminent`），其余控件保持中性玻璃。Paste 6、Raycast 的重设计验证了"克制染色"路线。
3. **虚线框 drop zone 被视为网页范式**；现代做法是玻璃卡片 + `.glassEffect(...).interactive()` 拖拽悬停高光，用材质边缘光代替描边。
4. **参数跟随系统**：圆角用 concentric 配置、阴影走系统默认，不写死数值（macOS 27 将把窗口圆角 26pt→20pt，Liquid Glass 仍在调整期）。
5. 关键 API：`GlassEffectContainer`、`.glassEffect(.regular.tint(...).interactive())`、`.buttonStyle(.glass/.glassProminent)`。
- 来源：[WWDC25 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) · [LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) · [Paste 6 Liquid Glass](https://pasteapp.io/blog/paste-in-liquid-glass) · [macOS 26 主题系统](https://www.macrumors.com/2025/06/13/macos-tahoes-new-theming-system-explained/)

### 5.3 直接竞品补充（相对 §3 的增量）

- **[Figura](https://github.com/nuance-dev/figura)——定位重合度最高的直接竞品**：免费、MIT、SwiftUI、macOS 14+、同样封装 Apple Vision。弱点：单窗口形态（无菜单栏/浮层/CLI/Finder 扩展/可选模型）、仅 GitHub 分发、111 star 个人维护、README 自称 AI 数小时写完的 v1。它证明需求存在，也是要超越的底线。
- **SpeedCut**（€16.99，[Gumroad](https://speedcut.gumroad.com/l/kidcwu)）：菜单栏一键抠图，证明"菜单栏形态抠图"已有人做，但付费闭源。
- **[EyeDrop](https://eyedrop.ai/)**（本地 AI 图片描述工具）：功能不同但产品哲学与 Pluck 镜像——"Drag. Drop. Describe."、完全离线、无订阅、结果自动进剪贴板（零步骤交付）。气质参考。
- Photoroom（设计口碑最好的抠图产品）**没有原生 Mac 客户端**；remove.bg/Photoroom 均强制上云+水印/credit 墙。**没有任何竞品做到"拖入即处理、处理完直接拖出"的零摩擦交互**——这是 Pluck 最无竞争者的一环。

### 5.4 第二轮原型的设计预设修订（据此改写 prototypes/prompts.md）

第一轮图（暖奶油底 + 大面积珊瑚橙 + 自绘控件）被判定为"2023 Web 风"，与 macOS 26 脱节。修订：**布局保留，皮肤换掉**——中性底色 + 真实玻璃材质透出壁纸、珊瑚橙用量砍到单点强调、控件回归系统形态、抠图结果（棋盘格上的主体）作为视觉主角。

---

## 附录 A：拿别人的题考自己（2026-07-28）

自己攒的 CC0 测试图有一个结构性问题：**是我们挑的**。挑图的人和写引擎的人是同一个人，就没有人在替失败的情况说话。所以补一套由别人挑、别人也公开了答案的图。

### A.1 能拿来即用的：rembg 官方样例（13 张）

[danielgatis/rembg](https://github.com/danielgatis/rembg)（MIT，★24k，开源侧事实标准）在 `examples/` 里放了 13 张输入 + 各自的 `.out.png` 输出，正是它 README 里用来展示自己的那批图：人像 3、动物 3、汽车 3、动漫 4、多肉植物架 1。`Scripts/qa-benchmark.sh` 拉图、跑我们的 CLI、拼三联对比图（原图 | rembg | pluck，洋红背景）、并算两边 alpha 二值化后的 IoU。图落在 gitignore 掉的 `qa/`——别人的图不该被我们的仓库镜像一份。

**注意 rembg 的输出不是 ground truth，只是第二种意见。** IoU 低只说明两个引擎不同意，谁对是眼睛的问题不是脚本的问题。

首次结果（Apple Vision，`VNGenerateForegroundInstanceMaskRequest`）：

| 分组 | IoU vs rembg |
|---|---|
| 人像 girl-1/2/3 | 96.6% / 98.7% / 99.1% |
| 动物 animal-1/2/3 | 95.3% / 98.6% / 97.5% |
| 汽车 car-1/2/3 | 98.5% / 99.0% / 98.5% |
| 动漫 anime-girl-1/2/3 | 94.1% / 93.3% / **81.9%** |
| 植物 plants-1 | **2.3%** |

结论三条：

1. **照片类基本打平**。人像/动物/汽车九张里七张 IoU > 97%，4× 放大看 girl-2 的金发边缘，Vision 甚至比 u2net 多留了右肩那一缕。"系统引擎凑合用"这个先入之见在这批图上不成立。
2. **plants-1 是 Vision 赢，而且赢得离谱**：rembg 只抠出画面中一个小盆栽（前景占比 0.8%），Vision 把整个两层花架连植物一起抠了出来（34.0%）。这是 `VNGenerateForegroundInstanceMask` **多实例**的结构性优势——它找的是"所有前景实例"，u2net 找的是"最显著的那一个"。
3. **动漫是唯一真实弱项**：anime-girl-3 只有 81.9%，我们多出 2.7 个百分点的前景。这类图是 v0.3 高质量模型的第一批目标场景，也是 before/after 营销图应该避开的题材。

### A.2 真要有 ground truth，得下这些（都不进仓库）

| 数据集 | 内容 | 体积 | 拿法 |
|---|---|---|---|
| **DIS-VD** | 470 张 2K–4K，GT 精细到镂空结构；BiRefNet/IS-Net 论文都报这个 | 456 MB（parquet） | HF `nobg/DIS5K`，split `DIS_VD` |
| **DIS-TE4** | 500 张，结构复杂度最高的一档，专治发丝/网格 | 643 MB | 同上，split `DIS_TE4` |
| **P3M-500-NP** | 人像 matting，非隐私保护版，有真 alpha 而非二值 mask | 266 MB | HF `nobg/P3M-10K`（MIT），split `P3M_500_NP` |

`DIS5K` 附 Terms of Use（研究用途），所以它只适合本机 QA，**不能**成为仓库里的 fixture，也不能出现在营销图里。P3M-10K 标的是 MIT，但人像数据的肖像权和 license 是两件事，同样只本机用。

### A.3 remove.bg 那边没有东西可拿

[github.com/remove-bg](https://github.com/remove-bg) 整个组织都是**商业 API 的客户端**（ruby gem / go CLI / serverless demo），没有模型也没有测试集——它们的模型是 BRIA 的 RMBG 系，CC BY-NC，早已因 license 排除在外（§2.2）。这条路是死的，不用再查。

### A.4 权重下载坐标（2026-07-28 逐个核实）

§2.2 的候选表列的是"有哪些模型"，没列"从哪儿拿、多少字节"。做 Core ML 转换 spike 和跑 DIS-VD 对比都需要本机有权重，于是把每个候选的真实下载地址和大小对着 Hugging Face / GitHub API 核了一遍，写成 `Scripts/fetch-models.sh`。

| 模型 | 权重文件 | 实测体积 | License | 用途 |
|---|---|---|---|---|
| **BiRefNet_lite** | `ZhengPeng7/BiRefNet_lite` → `model.safetensors` | 169.4 MB（44.4M 参数） | MIT | **v0.3 首选** |
| BiRefNet_lite ONNX | `onnx-community/BiRefNet_lite-ONNX` → `onnx/model.onnx` | 213.6 MB（fp16 版 109.2 MB） | MIT | 转换结果的交叉验证 |
| BiRefNet_lite-2K | `ZhengPeng7/BiRefNet_lite-2K` | 169.4 MB，输入 2560×1440 | MIT | 大图备选 |
| BiRefNet 完整版 | `ZhengPeng7/BiRefNet` | 423.9 MB（ONNX 927.6 MB） | MIT | 太大，不考虑 |
| InSPyReNet | `plemeri/InSPyReNet` | ~367 MB | MIT | 备胎；**GitHub 无 release asset**，权重走 Google Drive 或 `transparent-background` pypi |
| U²Net / U²Net-p | `u2net.onnx` / `u2netp.onnx` | 167.8 MB / 4.4 MB | Apache-2.0 | 只做基线 |
| IS-Net (DIS) | `isnet-general-use.onnx` | 170.4 MB | Apache-2.0 | 只做基线 |
| Silueta | `silueta.onnx` | 42.1 MB | Apache-2.0 | 只做基线（U²Net 瘦身版） |
| MODNet | — | ~26 MB | Apache-2.0 | 纯人像，场景太窄 |
| ~~RMBG-1.4~~ | `briaai/RMBG-1.4` | 168 MB | OpenRAIL-M ⚠️ | 排除 |
| ~~RMBG-2.0~~ | `briaai/RMBG-2.0` | 976.9 MB（INT8 CoreML 233 MB） | CC BY-NC ❌ | 排除，硬红线 |

四个 Apache-2.0 基线全部挂在 rembg 的 `v0.0.0` release（该 release 共 38 个 asset），路径规律是 `https://github.com/danielgatis/rembg/releases/download/v0.0.0/<name>.onnx`——这正是 A.1 里那些 `.out.png` 的出处，本机有了它们才可能在 DIS-VD 上跑整套对比，而不是只对着 13 张截图说话。

权重落在 `models/weights/`（已 gitignore，共 801 MB），下载后记 `SHA256SUMS`；v0.3 app 内的 manifest 会复用同一批摘要。**License 是闸门，不是体积**：BRIA 系两个模型在脚本里是刻意缺席的，且必须保持缺席。

### A.5 Core ML 转换 spike：可行，94 MB，0.6 秒（2026-07-28）

roadmap 标了半个月的"最大不确定项"今天有了答案。`Scripts/convert-birefnet.py` 把 BiRefNet_lite（169 MB fp32 safetensors）转成了 **94 MB 的 fp16 mlpackage**，1024×1024 单张 warm 推理 **0.59 秒**（M 系 GPU），与 PyTorch fp32 原模型对拍 **MAE 0.0001、二值 mask 一致率 99.99%**。此前不许写进文案的"140 MB"猜测作废，真实数字更好。

一路上的四个坑，全部有解，记下来防止复发：

1. **`torchvision.ops.deform_conv2d` 无 Core ML 对应**（decoder 的 ASPPDeformable 用它）。解法：用纯张量算子手写等价实现（显式 gather + 双线性插值），trace 前替换；与 torchvision 对拍误差 ~1e-5，含 mask/stride/dilation/多 offset-group 变体。
2. **swin 的 `torch.ceil(torch.tensor(H)/window)` trace 成 shape-(1,) 常量**，coremltools 的 `aten::Int` 处理器只认 0 维。解法：转换时给 `_cast` 加单元素解包垫片（输入尺寸固定，全是可折叠常量，无损）。
3. **`repeat_interleave` 被 lower 成 fp32 reps 的 `tile`**，MIL 拒收；**rank-6 reshape** 超 Core ML 的 rank-5 上限。解法：都发生在我们自己的 deform 重写里——mask 乘法改 broadcast、offset 保持原生通道布局做通道算术。
4. **ANE 编译失败**（`ANECCompile() FAILED`，deform 的 gather 链）。解法：`computeUnits = .cpuAndGPU` 加载。首次加载约 10 秒（编译缓存后消失），warm 0.59 秒。**PluckKit 的 CoreMLEngine 必须传同样的 compute units**，这是 v0.3 的实现约束。

复现：`Scripts/fetch-models.sh` 取权重和模型代码 → `.venv/bin/python Scripts/convert-birefnet.py`（venv：python3.12 + torch + coremltools）。归一化常数折进了输入层，Swift 侧只喂原始 CGImage。

质量抽查（Core ML 输出，对 rembg 官方样例）：girl-1 IoU 96.5%、animal-1 96.0%、anime-girl-3 83.5%（目检：金鱼是实心的，rembg 抠成半透明；四方对比里 BiRefNet 最干净）、plants-1 3.7%（和 Vision 一样抠整个花架——两个"多实例"引擎对 u2net 的"单显著体"）。
