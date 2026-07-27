# UI 原型图生成提示词 · 第二轮（发给 codex image-gen）

> 第一轮图（pluck-*.png，2026-07-27 上午）结论：信息架构成立，视觉风格判定为"暖色 Web 风"，与 macOS 26 Liquid Glass 脱节。
> 本轮依据 [research.md §五](../research.md) 的调研修订。第一轮讨论详情见 git 历史中的本文件旧版。

## 设计预设（第二轮修订版）

**沿用（第一轮已达成共识）：**

- **结果展示：棋盘格透明底**——属内容层，是界面的视觉主角
- **体验标杆：CleanShot X / Dropover / Paste 6**——小而美、原生质感

**图标（第二轮修订）：**

- **菜单栏图标：实心主体 + 虚线剪影**——主体被"拽走"后原位留下虚线轮廓，直接图解 pluck 这个动作；呼应系统 Remove Background 图标心智，18px 模板图标下可读。羽毛方案废弃（羽毛的既有心智是"写作"，双关需要注释才成立）。
- 羽毛元素可留给 app 大图标做彩蛋（非本轮范围）。

**修订（依据调研）：**

- **材质：真实 Liquid Glass，废弃奶油底色**。窗口用中性系统底色，功能层（浮层容器、按钮、工具栏）用玻璃材质透出壁纸；内容层（抠图结果、棋盘格、缩略图）不加玻璃。
- **珊瑚橙保留但用量砍到单点强调**：每屏最多一个染色主操作（主按钮/进度/选中勾），其余控件中性玻璃。
- **废弃虚线框 drop zone**：改为玻璃卡片 + 拖拽悬停高光（`.interactive()` 反馈），无描边。
- **控件回归系统形态**：设置窗口用原生 toolbar tab，按钮用 glass/glassProminent，不自绘。
- **浮层是产品灵魂**：出现在用户松手位置附近（Dropover 式零位移），结果即刻可拖走；一级操作只留 Copy / Save，换背景收进二级；约 5s 自动消失，悬停暂停。
- **圆角/阴影参数跟随系统**，原型图只需"看起来像原生"，不标注具体数值。
- 讨论定稿后：结论回写 [product-plan.md](../product-plan.md)，重大取舍记入 [decisions.md](../decisions.md)。

用法：整份发给 codex 用 [codex-brief.md](codex-brief.md)（前缀已内联、含文件名约定和 P6 图标专项）；本文件保留分条提示词作为讨论底稿。生成图存回本目录（p1-empty.png 等）。

## 共享风格前缀（每条提示词开头都带上）

> UI design mockup of a native macOS 26 Tahoe app called "Pluck", a background removal utility. Authentic Apple "Liquid Glass" design language: genuine translucent glass materials that subtly refract the desktop wallpaper behind them, neutral system window backgrounds (strictly no cream or beige tint), SF Pro typography, standard macOS controls, concentric rounded corners, soft system shadows, light mode. Accent color: warm coral — used with extreme restraint, on at most ONE primary action or status element per screen; every other control stays neutral glass. The cut-out subjects on checkerboard transparency are the visual heroes; the window chrome recedes behind the content. Overall it feels like a first-party Apple utility with the polish of CleanShot X or Paste 6. Render as a crisp high-fidelity screenshot on a blurred macOS wallpaper background.

## P1 — 主窗口 · 空状态

> [风格前缀] Main window, empty state, roughly 720×520, neutral background with a hint of wallpaper glow through the material. Centered: a large frosted-glass rounded card (no dashed border, no stroke — its edge is defined by the glass material's own rim light), containing an upward-arrow-into-tray glyph, headline "Drop images here", subline "or press ⌘V to paste". Bottom edge: a slim toolbar with a small shield glyph and "100% offline — photos never leave this Mac" on the left, a quiet gear icon on the right. Monochrome except nothing — this screen has zero coral. Radical simplicity.

## P2 — 主窗口 · 批量处理中

> [风格前缀] Main window during batch processing. A compact vertical queue of 5 rows on the neutral window background: each row has a small square thumbnail (checkerboard transparency with the cut-out subject), filename in SF Pro, and a status glyph at right — three rows show a subtle gray checkmark "Done", one row shows a thin coral progress ring at 60%, one shows gray "Waiting". Top: quiet summary text "3 of 5 done" with a hairline overall progress bar in coral. Bottom toolbar: two neutral glass pill controls "PNG ▾" and "Transparent ▾" on the left, and one coral glass-prominent button "Export All…" on the right — the only saturated element besides the progress indicators.

## P3 — 菜单栏 Popover（主入口）

> [风格前缀] A macOS 26 menu bar with a small monochrome template icon among the status icons: a tiny solid blob-shaped subject floating just above a dashed outline of the same shape — a subject plucked out of its background. Below it a Liquid Glass popover, about 340×440, clearly refracting the blurred wallpaper behind it. Top: a frosted-glass drop strip with an image glyph and "Drop image or ⌥⌘B to pluck clipboard" (no dashed border on the strip). Middle: "Recent" label, then a 3-column grid of 6 small thumbnails, each a checkerboard-transparency tile with a cut-out subject; one tile shows hover state with two tiny glass glyph buttons (copy, save). Footer: "Open Pluck" text button left, small pause toggle right, both neutral. No coral anywhere in this screen.

## P4 — 处理完成浮层（产品灵魂）

> [风格前缀] A small Liquid Glass floating panel that has just appeared near the mouse cursor on a blurred desktop (not pinned to a screen corner), about 280×320, glass container refracting the wallpaper, soft system shadow, a subtle grab-handle bar at top. It shows a freshly cut-out dog on checkerboard transparency — the image area itself is solid content, not glassy — with a small "Before" ghost pill at its top-left corner. Below the image: a single row of three controls — two circular neutral glass icon buttons ("Copy", "Save") and one small "···" overflow button; no other chrome. The panel looks like a sticker you could immediately drag into another app; a faint caption below reads "drag me · fades in 5s".

## P5 — 设置 · 模型管理

> [风格前缀] Settings window, "Models" tab, about 560×420, standard macOS 26 settings chrome: native toolbar with tab items General · Models · Shortcuts · About rendered as system controls (not custom-drawn cards). Content: two engine rows in a plain grouped list. Row 1 selected with a single coral checkmark: "Apple Vision" with gray badges "Built-in · 0 MB", subtitle "Instant, great for everyday photos". Row 2: "BiRefNet Lite" with badges "MIT license · 140 MB", subtitle "Finer edges — hair, fur, glass", and a neutral glass "Download" button with a small cloud glyph. Footer: quiet footnote with a shield glyph, "Models are downloaded once, stored locally, and never phone home." Everything neutral except that one coral checkmark.

## 第二轮讨论清单

- 入口层级：菜单栏为主、主窗口降级为批量专用——成立吗？主窗口还需要空状态吗（P1 是否该被 P3+P4 取代）？
- P4 浮层出现位置：跟随松手位置（Dropover 式） vs 固定右下角（CleanShot X 式）——原型图按前者画，实际拖拽场景是否会遮挡目标？
- P4 一级操作砍到 Copy/Save + 溢出菜单——"换背景"降级后，非透明底导出的入口够不够显眼？
- 珊瑚橙砍量后品牌识别度是否还够？"主体+虚线剪影"图标 + 单点橙是否足以建立记忆点？
- 新菜单栏图标在 18px 下虚线是否还可辨？（出图后缩小验证）
- 玻璃材质在 image-gen 里容易画过头——第二轮图如果出现"塑料感"，以真机系统控件截图为准，不以图为准。
