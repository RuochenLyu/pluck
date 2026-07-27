# Codex 出图任务书 · Pluck UI 原型第二轮

一次性生成 **6 张图**，每张对应下方一个编号任务。要求：

- 每个任务的提示词**独立完整**（风格前缀已内联），逐条生成，互不引用。
- 生成结果存到 `docs/prototypes/`，文件名：`p1-empty.png`、`p2-batch.png`、`p3-menubar.png`、`p4-floating.png`、`p5-settings.png`、`p6-icon.png`。
- 横竖比按提示词中的尺寸描述取近似即可。
- 全部完成后列出生成的文件清单，不需要自评。

---

## P1 — 主窗口 · 空状态 → `p1-empty.png`

UI design mockup of a native macOS 26 Tahoe app called "Pluck", a background removal utility. Authentic Apple "Liquid Glass" design language: genuine translucent glass materials that subtly refract the desktop wallpaper behind them, neutral system window backgrounds (strictly no cream or beige tint), SF Pro typography, standard macOS controls, concentric rounded corners, soft system shadows, light mode. Accent color: warm coral — used with extreme restraint, on at most ONE primary action or status element per screen; every other control stays neutral glass. The cut-out subjects on checkerboard transparency are the visual heroes; the window chrome recedes behind the content. Overall it feels like a first-party Apple utility with the polish of CleanShot X or Paste 6. Render as a crisp high-fidelity screenshot on a blurred macOS wallpaper background.

Main window, empty state, roughly 720×520, neutral background with a hint of wallpaper glow through the material. Centered: a large frosted-glass rounded card (no dashed border, no stroke — its edge is defined by the glass material's own rim light), containing an upward-arrow-into-tray glyph, headline "Drop images here", subline "or press ⌘V to paste". Bottom edge: a slim toolbar with a small shield glyph and "100% offline — photos never leave this Mac" on the left, a quiet gear icon on the right. This screen has zero coral. Radical simplicity.

## P2 — 主窗口 · 批量处理中 → `p2-batch.png`

UI design mockup of a native macOS 26 Tahoe app called "Pluck", a background removal utility. Authentic Apple "Liquid Glass" design language: genuine translucent glass materials that subtly refract the desktop wallpaper behind them, neutral system window backgrounds (strictly no cream or beige tint), SF Pro typography, standard macOS controls, concentric rounded corners, soft system shadows, light mode. Accent color: warm coral — used with extreme restraint, on at most ONE primary action or status element per screen; every other control stays neutral glass. The cut-out subjects on checkerboard transparency are the visual heroes; the window chrome recedes behind the content. Overall it feels like a first-party Apple utility with the polish of CleanShot X or Paste 6. Render as a crisp high-fidelity screenshot on a blurred macOS wallpaper background.

Main window during batch processing. A compact vertical queue of 5 rows on the neutral window background: each row has a small square thumbnail (checkerboard transparency with the cut-out subject), filename in SF Pro, and a status glyph at right — three rows show a subtle gray checkmark "Done", one row shows a thin coral progress ring at 60%, one shows gray "Waiting". Top: quiet summary text "3 of 5 done" with a hairline overall progress bar in coral. Bottom toolbar: two neutral glass pill controls "PNG ▾" and "Transparent ▾" on the left, and one coral glass-prominent button "Export All…" on the right — the only saturated element besides the progress indicators.

## P3 — 菜单栏 Popover（主入口）→ `p3-menubar.png`

UI design mockup of a native macOS 26 Tahoe app called "Pluck", a background removal utility. Authentic Apple "Liquid Glass" design language: genuine translucent glass materials that subtly refract the desktop wallpaper behind them, neutral system window backgrounds (strictly no cream or beige tint), SF Pro typography, standard macOS controls, concentric rounded corners, soft system shadows, light mode. Accent color: warm coral — used with extreme restraint, on at most ONE primary action or status element per screen; every other control stays neutral glass. The cut-out subjects on checkerboard transparency are the visual heroes; the window chrome recedes behind the content. Overall it feels like a first-party Apple utility with the polish of CleanShot X or Paste 6. Render as a crisp high-fidelity screenshot on a blurred macOS wallpaper background.

A macOS 26 menu bar with a small monochrome template icon among the status icons: a tiny solid blob-shaped subject floating just above a dashed outline of the same shape — a subject plucked out of its background. Below it a Liquid Glass popover, about 340×440, clearly refracting the blurred wallpaper behind it. Top: a frosted-glass drop strip with an image glyph and "Drop image or ⌥⌘B to pluck clipboard" (no dashed border on the strip). Middle: "Recent" label, then a 3-column grid of 6 small thumbnails, each a checkerboard-transparency tile with a cut-out subject; one tile shows hover state with two tiny glass glyph buttons (copy, save). Footer: "Open Pluck" text button left, small pause toggle right, both neutral. No coral anywhere in this screen.

## P4 — 处理完成浮层（产品灵魂）→ `p4-floating.png`

UI design mockup of a native macOS 26 Tahoe app called "Pluck", a background removal utility. Authentic Apple "Liquid Glass" design language: genuine translucent glass materials that subtly refract the desktop wallpaper behind them, neutral system window backgrounds (strictly no cream or beige tint), SF Pro typography, standard macOS controls, concentric rounded corners, soft system shadows, light mode. Accent color: warm coral — used with extreme restraint, on at most ONE primary action or status element per screen; every other control stays neutral glass. The cut-out subjects on checkerboard transparency are the visual heroes; the window chrome recedes behind the content. Overall it feels like a first-party Apple utility with the polish of CleanShot X or Paste 6. Render as a crisp high-fidelity screenshot on a blurred macOS wallpaper background.

A small Liquid Glass floating panel that has just appeared near the mouse cursor on a blurred desktop (not pinned to a screen corner), about 280×320, glass container refracting the wallpaper, soft system shadow, a subtle grab-handle bar at top. It shows a freshly cut-out dog on checkerboard transparency — the image area itself is solid content, not glassy — with a small "Before" ghost pill at its top-left corner. Below the image: a single row of three controls — two circular neutral glass icon buttons ("Copy", "Save") and one small "···" overflow button; no other chrome. The panel looks like a sticker you could immediately drag into another app; a faint caption below reads "drag me · fades in 5s".

## P5 — 设置 · 模型管理 → `p5-settings.png`

UI design mockup of a native macOS 26 Tahoe app called "Pluck", a background removal utility. Authentic Apple "Liquid Glass" design language: genuine translucent glass materials that subtly refract the desktop wallpaper behind them, neutral system window backgrounds (strictly no cream or beige tint), SF Pro typography, standard macOS controls, concentric rounded corners, soft system shadows, light mode. Accent color: warm coral — used with extreme restraint, on at most ONE primary action or status element per screen; every other control stays neutral glass. The cut-out subjects on checkerboard transparency are the visual heroes; the window chrome recedes behind the content. Overall it feels like a first-party Apple utility with the polish of CleanShot X or Paste 6. Render as a crisp high-fidelity screenshot on a blurred macOS wallpaper background.

Settings window, "Models" tab, about 560×420, standard macOS 26 settings chrome: native toolbar with tab items General · Models · Shortcuts · About rendered as system controls (not custom-drawn cards). Content: two engine rows in a plain grouped list. Row 1 selected with a single coral checkmark: "Apple Vision" with gray badges "Built-in · 0 MB", subtitle "Instant, great for everyday photos". Row 2: "BiRefNet Lite" with badges "MIT license · 140 MB", subtitle "Finer edges — hair, fur, glass", and a neutral glass "Download" button with a small cloud glyph. Footer: quiet footnote with a shield glyph, "Models are downloaded once, stored locally, and never phone home." Everything neutral except that one coral checkmark.

## P4-r2 — 浮层返工（2026-07-27 追加）→ `p4-floating.png`（返工版已取代首版，定稿即此文件名）

> 首版 p4 的三个问题：面板过大留白失控、提示文字占版面、光标未贴近面板。返工版要求：260×300、图像满铺无玻璃留白、无任何文字标签、倒计时改为底边珊瑚细线、光标紧贴面板左上角。

UI design mockup of a native macOS 26 Tahoe app called "Pluck", a background removal utility. Authentic Apple "Liquid Glass" design language: genuine translucent glass materials that subtly refract the desktop wallpaper behind them, SF Pro typography, standard macOS controls, concentric rounded corners, soft system shadows, light mode. Accent color: warm coral — used with extreme restraint. Render as a crisp high-fidelity screenshot on a blurred macOS wallpaper background.

A compact Liquid Glass floating panel that has JUST appeared directly beside the mouse cursor — the arrow cursor is immediately adjacent to the panel's top-left corner, almost touching it. The panel is small and tight, about 260×300: the freshly cut-out dog on checkerboard transparency fills the panel edge-to-edge with NO glass margin around the image; only a slim glass bar below the image holds a single row of three small circular neutral glass icon buttons (copy glyph, save glyph, "···"). A tiny "Before" ghost pill overlays the image's top-left corner. A hairline coral progress line runs along the panel's bottom edge, half depleted — indicating the auto-dismiss countdown. No text labels, no captions, no grab handle — the chrome is nothing but the image, three buttons, and that hairline. It reads as a sticker you could instantly drag into another app.

## P6 — 菜单栏图标专项（放大稿）→ `p6-icon.png`

Icon design sheet for a macOS menu bar template icon, called "Pluck" (background removal utility). The concept: a solid blob-shaped subject lifted slightly above a dashed outline of the same shape below it — a subject plucked out of its background, leaving a dashed silhouette behind. Show the glyph large (512px) in pure black on white, then repeated at 18px menu-bar size in both light and dark macOS menu bar strips to verify legibility. Minimal, geometric, consistent with SF Symbols stroke weight. 3-4 variations: different blob shapes (organic blob, star-like, person silhouette), different lift distances.
