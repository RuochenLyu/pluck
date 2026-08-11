# cat-1 · Icon Composer layers

Production layers derived from the approved `cat-1` direction.

## Deliverables

- `layer-card.png` — isolated warm-white photo card with a sunset scene and matching sitting-cat negative space.
- `layer-cat.png` — isolated coral sitting-cat silhouette.
- `layer-background-coral.png` — opaque `#FFB38A → #FF7A5C` background candidate.
- `layer-background-cream.png` — opaque `#FFF4EA → #FFE3D2` background candidate.

All files are 1024×1024 PNGs. The card and cat layers use RGBA transparency; the background candidates are intentionally opaque.

`sources/` contains the flat chroma-key ImageGen outputs used to derive the two transparent layers.

## ImageGen prompts

The approved `cat-1` image was supplied as a pose, composition, and style reference. The built-in ImageGen path generated each layer separately on a uniform `#00ff00` chroma-key background; the installed ImageGen helper then produced the final alpha PNGs with soft matte, despill, and a 1 px edge contraction.

### Card

```text
Use case: logo-brand
Asset type: isolated Icon Composer layer for the Pluck macOS app icon
Input image: cat-1 is a composition and visual-style reference only; generate a new isolated photo-card layer, not an edit
Primary request: a single warm-white photo card standing upright with a very slight counterclockwise tilt of about 5 degrees. Inside the card, show one smooth sky gradient from peach to soft orange, one simple dune-shaped hill band, and one small pale sun disc. In the card is one clean sitting-cat-shaped warm-white #FCFAF6 negative-space hole, with upright ears and a tail curled around the body. There is no cat, only the matching hole.
Style/medium: simpler than the reference; flat modern illustration; minimal soft gradient; large clean shapes; crisp edges; designed for Apple Icon Composer glass rendering
Composition/framing: square 1:1; card centered; entire card contained within the central 70% of the canvas, leaving at least 15% clear padding on all four sides
Scene/backdrop: perfectly flat solid #00ff00 chroma-key background for removal
Constraints: nothing outside the card; no shadows; no highlights; no outlines; no text; no watermark; no glass effect; no extra scenery; no checkerboard. The #00ff00 background must be one exact uniform color with no gradients, texture, reflections, floor plane, or lighting variation. Keep the card fully separated from the background. Do not use #00ff00 in the card.
```

### Cat

```text
Use case: logo-brand
Asset type: isolated Icon Composer foreground layer for the Pluck macOS app icon
Input image: cat-1 is a pose and visual-style reference only; generate a new isolated cat layer, not an edit
Primary request: one sitting cat silhouette with upright ears and a tail curled around the body, matching the iconic pose family of the cat and hole in the reference. Fill the entire cat with a smooth coral gradient #FF8C66 to #EE4B45. It must be one completely solid connected shape with clean crisp edges and no interior gaps.
Style/medium: simpler than the reference; flat modern illustration; large clean silhouette; designed for Apple Icon Composer glass rendering
Composition/framing: square 1:1; cat centered; entire cat contained within the central 70% of the canvas, leaving at least 15% clear padding on all four sides
Scene/backdrop: perfectly flat solid #00ff00 chroma-key background for removal
Constraints: no shadows; no highlights; no outlines; no text; no face details; no paws drawn as separate lines; no watermark; no glass effect. The #00ff00 background must be one exact uniform color with no gradients, texture, reflections, floor plane, or lighting variation. Keep the cat fully separated from the background. Do not use #00ff00 in the cat.
```

## Validation

| Layer | Alpha bounding box | Transparent margins (L/T/R/B) | Corner alpha | Visible green fringe |
|---|---:|---:|---:|---:|
| Card | `185,163–845,862` | `185 / 163 / 179 / 162` | `0 / 0 / 0 / 0` | `0 px` |
| Cat | `289,155–761,864` | `289 / 155 / 263 / 160` | `0 / 0 / 0 / 0` | `0 px` |

The required 15% margin is 154 px at 1024×1024; both layers clear it on all four sides.

## Icon Composer placement

Bottom to top: selected bright gradient background → card at roughly 62%, slightly left and down → cat at roughly 48%, shifted toward the upper right so it crosses the card edge and separates visibly from the matching hole. Apply glass, highlights, and appearance variants only in Icon Composer.
