# ImageGen prompt set

All prompts used the following shared specification, replacing `[SUBJECT]` and `[DETAIL]` for each group.

```text
Use case: logo-brand
Asset type: macOS 26 app icon concept exploration for Pluck, a native offline background-removal app
Primary request: modern flat illustrated macOS app icon. A slightly tilted warm-white photo card sits on a deep teal full-bleed square background. Inside the card is a simple sunset scene with only a sky gradient, distant hills, and a small sun. A coral-colored [SUBJECT] has visibly been lifted OUT of the photo and floats above and beyond the card edge, leaving a pale empty hole of exactly the same recognizable shape inside the card. The lifted subject is the unmistakable focal point and the extraction relationship must read instantly.
Subject: [DETAIL]
Style/medium: modern flat illustration with soft gradients; bold rounded shapes; crisp clean edges; low detail; vector-friendly; not photorealistic; not 3D
Composition/framing: square 1:1, full bleed, centered, key elements within the central 80% safe area; card visibly tilted; subject clearly separated from and overlapping beyond the card
Lighting/mood: calm, polished, friendly; no dramatic highlights
Color palette: maximum five hues; coral subject gradient #FF8C66 to #EE4B45; warm-white card #FCFAF6; deep teal background #16383E; restrained sunset accents
Constraints: strong silhouette readable at 32x32; three unmistakable layers: dark background, white card, coral subject; card scene has no more than three elements; no outline style; no text, letters, watermark, checkerboard, transparency grid, drawn rounded-corner frame, border, glass effect, external glow, photorealism, 3D render, busy detail, or cast shadow outside the canvas
```

Subject substitutions:

- Portrait: `[SUBJECT]` = `illustrated portrait of a person`; `[DETAIL]` = `recognizable head-and-shoulders portrait with a clear hairstyle silhouette and a simple shirt collar, not two abstract ovals`.
- Cat: `[SUBJECT]` = `sitting cat`; `[DETAIL]` = `cute sitting cat silhouette with two clear upright ears, compact body, paws implied by broad shapes, and one curled tail; iconic and recognizable at tiny size`.
- Flower: `[SUBJECT]` = `single tulip plant`; `[DETAIL]` = `one stylized tulip bloom with a sturdy curved stem and two broad distinct leaves; concrete botanical silhouette, no pot, recognizable at tiny size`.

Each subject used these six controlled composition variants:

1. Rise diagonally from the card center; emphasize a clean matching void.
2. Hook over the upper-right card edge; make the matching void large and obvious.
3. Lift vertically with a small clean gap; use a gentle card tilt and near symmetry.
4. Counter-rotate card and subject for a dynamic but simple extraction gesture.
5. Enlarge and simplify the subject, optimizing ruthlessly for 32 px readability.
6. Use the most minimal iconic interpretation while preserving the subject-defining features.
