# UI 原型图生成提示词（发给 codex image-gen）

用法：每个提示词单独发一次。所有提示词共享同一段风格前缀，保证系列图风格一致。
生成的图存回本目录（p1-main-empty.png 等），基于图片讨论后把结论写进 product-plan.md。

## 共享风格前缀（每条提示词开头都带上）

> UI design mockup of a native macOS 26 app called "Pluck", a background removal tool. Modern Apple design language: translucent materials, SF Pro typography, generous whitespace, rounded corners, subtle shadows, light mode. Accent color: a warm coral/tangerine. The app feels minimal and premium, like CleanShot X or Rectangle — a small focused utility, not a bloated photo editor. Render as a crisp high-fidelity screenshot on a plain neutral background.

## P1 — 主窗口 · 空状态（第一印象）

> [风格前缀] Main window, empty state, roughly 720×520. A single large drop zone fills the window: dashed rounded border, centered upward-arrow-into-tray icon, headline "Drop images here", subline "or press ⌘V to paste · your photos never leave this Mac". Bottom edge has a slim toolbar: left shows a small shield icon with "100% offline", right shows a quiet settings gear. No sidebar, no menus, radical simplicity.

## P2 — 主窗口 · 批量处理中

> [风格前缀] Main window during batch processing. A vertical queue of 5 image rows, each row: small square thumbnail with checkerboard-transparency background showing the cut-out subject, filename, and a status at right — three rows show a coral checkmark "Done", one row shows a circular progress ring at 60%, one row shows a gray "Waiting". Top of window: summary line "3 of 5 done" with a thin overall progress bar. Bottom toolbar: "Export All to…" primary button in coral, and a segmented control "PNG / Background: transparent".

## P3 — 菜单栏 Popover

> [风格前缀] A macOS menu bar at the top of the screen with a small feather icon among the status icons; below it hangs an open popover, about 320×420. Popover content: at top a compact drop target strip "Drop image or ⌥⌘B to pluck clipboard"; below, a "Recent" section with a 2×2 grid of thumbnails on checkerboard-transparency backgrounds; each thumbnail shows tiny hover actions (copy icon, save icon). Footer row: "Open Pluck" and a pause toggle. Background of the screen is a blurred macOS desktop wallpaper.

## P4 — 处理完成浮层（CleanShot X 式）

> [风格前缀] A small floating result panel in the bottom-right corner of a blurred desktop, about 300×360, elevated with a soft shadow. It shows the just-processed image: a dog cut out cleanly, displayed on a checkerboard transparency pattern, with a subtle "before" ghost toggle at top. Below the image, a horizontal row of four glyph buttons with tiny labels: "Copy", "Save", "Drag me", "Background ▾". A tiny caption under the panel: "auto-dismisses in 8s". The panel looks grabbable, like a sticker you could drag into another app.

## P5 — 设置 · 模型管理

> [风格前缀] Settings window, "Models" tab, about 560×420. A list of two engine cards. Card 1 (selected, coral border): "Apple Vision" with badges "Built-in · 0 MB · macOS", subtitle "Instant, great for everyday photos". Card 2: "BiRefNet Lite" with badges "MIT license · 140 MB", subtitle "Finer edges — hair, fur, glass", and a "Download" button with a small cloud icon. Below the cards, a quiet footnote: "Models are downloaded once, stored locally, and never phone home." Top of window has standard macOS settings tab bar: General · Models · Shortcuts · About.

## 讨论清单（拿到图后过一遍）

- P1：空状态是否传达了"拖进来就行 + 离线"两个信息？窗口比例合适吗？
- P2：批量队列信息密度——要不要缩略图对比（原图/结果）？
- P3：菜单栏是主入口还是辅助入口？Recent 网格有没有必要？
- P4：浮层按钮取舍——"换背景"值得放一级入口吗？自动消失时长？
- P5：两张引擎卡片的措辞能否让非技术用户理解"要不要下载"？
