# Pluck 应用图标 · 绘图任务书

> 交给绘图 agent（Codex 等）的自包含任务书。产出为手写 SVG，不依赖任何外部素材或字体。

## 产品是什么

**Pluck** — macOS 原生离线抠图（remove background）应用。品牌语：*"Pluck — lift subjects out of photos. Offline, free, open source."* 一句话：把主体从照片里拎出来，背景消失。

## 你要画什么

macOS 26（Tahoe）风格的应用图标。核心叙事**必须一眼读出"把主体从照片/背景中取出来"**——这是一个去背景工具，不是相册、不是滤镜、不是水果店。

**已定的构图母题**（在此基础上发挥）：一张倾斜的照片卡片，卡片里的**主体已经被拎出来**，悬在卡片上方/边缘之外；卡片上留着主体形状的**浅色空洞**。取出的主体是图标的视觉焦点。

**要求具象、有插画感**——上一轮用纯几何色块做的验证稿被否，理由是"太抽象"。照片卡里要有可辨认的场景元素（例如：远山 + 天空渐变 + 太阳），被拎出的主体要具象可爱。主体三选一，各出一个方案：

1. **人像**：头肩剪影但带插画细节（发型轮廓、衣领），不是两个椭圆。
2. **猫**：坐姿猫剪影（立耳 + 尾巴卷起），轮廓性极强，小尺寸依然可辨。
3. **花 / 盆栽**：单支郁金香或圆叶盆栽，茎叶形态清晰。

## 视觉规范（硬约束）

- **画布**：1024×1024。系统会裁切圆角方形并加投影——你交**满幅方形**设计，四角不用自己画圆角；关键元素放在中央 ~820×820 安全区内。
- **分层**：SVG 顶层 `<g>` 按此命名分组，之后要导入 Icon Composer 逐层渲染玻璃效果：
  - `id="background"`（底色/环境）
  - `id="photo-card"`（照片卡 + 卡内场景 + 空洞）
  - `id="subject"`（被拎出的主体）
- **风格**：现代扁平插画 + 柔和渐变。层次少、形状饱满、轮廓干净。**不要**：写实照片感、强烈自绘高光（玻璃光效系统会加）、外发光、描边风格、任何文字或字母、**棋盘格**（明确禁止——会被误读为图标本身透明）。
- **颜色**：
  - 主体色 = 品牌珊瑚：渐变 `#FF8C66 → #EE4B45`。
  - 照片卡 = 暖白 `#FCFAF6`；卡内场景配色自由但克制（建议黄昏天空系或青绿系）。
  - 底色建议深色（深青 `#16383E` 系或深靛），衬托白卡与珊瑚主体；也可提交一个浅底变体。
  - 全图不超过 5 个色相。
- **小尺寸可读**（验收硬标准）：缩到 32×32 时，仍能分辨"深底 + 白卡 + 珊瑚主体"三层，主体轮廓不糊成团。细节密度按此倒推——卡内场景元素不超过 3 个。

## 交付物

1. `icon-portrait.svg`、`icon-cat.svg`、`icon-flower.svg` —— 三个主体方案，各 1024×1024，按上述分层分组，纯手写路径（无嵌入位图、无外部引用、无滤镜依赖——`<linearGradient>`/`<radialGradient>` 可用，`<filter>` 模糊仅限背景层内小范围使用）。
2. 每个 SVG 附带一行渲染验证命令的说明（例如 `rsvg-convert -w 1024` 或 `qlmanage -t -s 1024`），确保无警告出图。
3. 一个 `preview.md`：三个方案各附 1024 与 32 两档 PNG 的导出说明。

## 验收标准

- [ ] 三个 SVG 独立打开渲染正确，无外部依赖
- [ ] 图层分组命名符合规范（background / photo-card / subject）
- [ ] 32px 下三层结构与主体轮廓清晰可辨
- [ ] 无棋盘格、无文字、无写实照片元素
- [ ] 叙事测试：给没见过产品的人看 1024 版，能说出"从照片里抠东西/取出来"的含义

## 参考锚点

- CleanShot X、Pixelmator Pro 的图标策略：单一具象物 + 简单底，层次极少但形状讲究。
- Apple HIG "App icons"（macOS 26 / Icon Composer 分层规范）：设计做减法，光效交给系统。

---

## 附：图像生成版（概念探索用）

> 用图像生成模型（gpt-image-1 / Midjourney 等）快速出概念，人工筛选后再按上文规范矢量重建。
> 生成图直接当图标用的两个已知限制：无法分层进 Icon Composer（拿不到系统玻璃光效）、小尺寸可读性靠运气——所以生成只负责"找到对的感觉"。

### 主 Prompt（每次替换 [SUBJECT] 为 portrait of a person / sitting cat / tulip flower）

```
macOS app icon for a background-removal tool, modern flat illustration
with soft gradients. Composition: a slightly tilted warm-white photo
card on a deep teal background; inside the card a simple sunset scene
(sky gradient, distant hills, small sun); a coral-colored [SUBJECT]
silhouette has been lifted OUT of the photo and floats above the
card's edge, leaving a pale empty hole of the same shape inside the
card. The lifted subject is the focal point. Bold rounded shapes,
maximum 5 hues, generous negative space, crisp clean edges, no
outlines, no text. Square 1:1, full-bleed, centered composition with
20% safe margin. Coral gradient #FF8C66 to #EE4B45 for the subject,
warm white #FCFAF6 card, deep teal #16383E background.
```

### 负面约束（支持 negative prompt 的模型使用）

```
no checkerboard pattern, no transparency grid, no text, no letters,
no photorealism, no 3D render, no glass effect, no drop shadows
outside the canvas, no rounded-corner frame drawn into the image,
no borders, no watermark
```

### 出图与筛选

- 每个主体至少 6 张，1024×1024 或以上。
- 筛选硬标准（淘汰制）：
  1. 缩到 32×32：深底 / 白卡 / 珊瑚主体三层仍可辨，主体轮廓不糊；
  2. 叙事测试：没见过产品的人能说出"从照片里取出来"；
  3. 卡内场景元素 ≤3 个，无碎细节；
  4. 不含棋盘格 / 文字 / AI 味过重的过度光影。
- 选中 1-2 张后：按本文上半部分的分层 SVG 规范重建（矢量化时允许对形状做简化，以 32px 可读为准），或位图直接精修出 icns（放弃 Liquid Glass 分层，接受平面图标）。
