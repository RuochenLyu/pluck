---
name: pluck
description: Remove image backgrounds on a Mac, fully offline, with the `pluck` CLI. Use when the user wants to cut out / extract a subject, remove or replace a background, make a photo transparent, or batch-produce transparent PNGs.
---

# Pluck — remove image backgrounds offline

`pluck` lifts the subject out of a photo and writes a transparent PNG. Everything runs
on-device (Apple Vision, or an optional Core ML model). No account, no upload, no network
except an explicit `pluck models pull`.

## When to use this

- "Remove the background from these photos"
- "Make this logo/product shot transparent"
- "Put this person on a white background"
- Batch-preparing cutouts for a deck, a store listing, a sprite sheet

## When not to use it

- It is **not** a general image editor: no crop, resize, filters, format conversion.
  Output is always PNG.
- Photos with no clear foreground subject (landscapes, textures, flat scans) legitimately
  produce **exit 2 / `no_subject`**. That is an answer, not a bug — don't retry in a loop.
- macOS 26+ only.

## Install

Pluck is pre-1.0 and ships from source. Build the CLI:

```bash
git clone https://github.com/RuochenLyu/pluck.git
cd pluck
swift build --product pluck          # binary at .build/debug/pluck
```

A Homebrew formula (`brew install pluck`) is planned for 1.0; it does not exist yet.

Models are optional. Apple Vision is built in and needs no download. Pull an extra engine
only when the user asks for better edges:

```bash
pluck models list                    # what this machine can use
pluck models pull birefnet-lite      # ~83 MB, MIT
```

## Core usage

```bash
pluck photo.jpg                      # → photo.png beside the input
pluck a.jpg b.jpg c.jpg -o out/      # batch; out/ is created if missing
pluck photo.jpg -o hero.png          # single input, exact output path
cat photo.jpg | pluck - > cut.png    # stdin → stdout
pluck photo.jpg --background '#ffffff'
pluck photo.jpg --model birefnet-lite-matting
pluck photo.jpg --force              # overwrite an existing output
```

### `-o` semantics (read this before scripting it)

`-o` is one flag with two meanings, resolved by these rules in order:

1. Path exists and is a directory → **directory**.
2. Trailing `/` → **directory** (even `-o 'out.png/'`).
3. Leading dot with no stem (`-o .png`) → **refused**, exit 1 (`bad_arguments`). It would
   name a hidden file, which nobody means.
4. Extension is `.png` (case-insensitive) → **single file**. Requires exactly one input,
   otherwise exit 1.
5. Anything else → **directory**.

Without `-o`, each result is written next to its input with the extension swapped to `.png`.

Two other refusals, both by design:

- An existing output file is **not** overwritten: `output_exists`, exit 1. Pass `--force`.
- Two inputs that map to the same output (`a/x.jpg b/x.jpg -o out/`) — the second one
  fails with `output_exists`. Comparison is **case-folded**, so `X.jpg` and `x.jpg` collide
  too; the default macOS volume is case-insensitive and a silent clobber would be data loss.

### stdin / stdout

`-` reads one image from stdin and writes the PNG to stdout. It cannot be combined with
other inputs, with `-o`, or with `--json` (the PNG owns stdout in that mode) — each is
exit 1.

### `--model`

| id | good for |
|---|---|
| `vision` (default) | everything, instant, zero download. Apple's foreground segmentation. |
| `birefnet-lite` | crisp hard-edged objects: products, logos, packaging, vehicles. Renders semi-transparent things (glassware) as solid. |
| `birefnet-lite-matting` | hair, fur, smoke, glass — keeps real partial transparency and soft edges. |

The two BiRefNet models are a **subject-matter split, not a quality ladder**: same size
(~83 MB each), same speed, same MIT license. Pick by what is in the picture.

### `--background`

Hex color, with or without `#`, in `rgb` / `rgba` / `rrggbb` / `rrggbbaa` form.
Default is transparent. An unparseable value is exit 1 (`bad_arguments`).

## `--json` contract

`--json` writes **NDJSON to stdout**: one object per line, no wrapping array. Every human
message (progress, errors in prose) goes to stderr, so stdout is safe to pipe into a parser.

Records are emitted **in input order**, regardless of the order the work finished in.

**Success record** — all fields always present:

```json
{"input":"product-02.jpg","output":"product-02.png","width":960,"height":664,"durationMs":277,"engine":"vision","ok":true}
```

| field | type | meaning |
|---|---|---|
| `input` | string | the path exactly as you passed it; `-` for stdin |
| `output` | string | the file that was written |
| `width` / `height` | number | pixels of the written PNG |
| `durationMs` | number | wall time for this image |
| `engine` | string | the engine id that actually ran |
| `ok` | bool | `true` |

**Item failure record** — same shape minus what does not exist:

```json
{"input":"nosubject-01.jpg","output":"nosubject-01.png","error":"no_subject","message":"nosubject-01.jpg: No subject was detected in this image.","engine":"vision","ok":false}
```

| field | notes |
|---|---|
| `input` | always present |
| `output` | present whenever a destination was known — i.e. the file that did *not* appear |
| `error` | stable slug, branch on this (see table below) |
| `message` | English prose for a human; do not parse |
| `engine` | tells you whether retrying with a different `--model` could help |
| `ok` | `false` |

**Run-level failure record** — the run died before it had any items (bad argument, unknown
or uninstalled model). Exactly one line, no `input`/`output`:

```json
{"error":"model_missing","message":"unknown model “nope”. installed models: vision","ok":false}
```

### `error` slugs

| slug | meaning |
|---|---|
| `no_subject` | nothing to cut out |
| `image_load_failed` | not a readable image |
| `engine_unavailable` | the engine cannot run on this machine |
| `model_missing` | model unknown or not installed |
| `model_load_failed` | model on disk but unusable |
| `model_download_failed` | a `models pull` failed |
| `manifest_invalid` | bundled model manifest unreadable |
| `processing_failed` | anything else inside the engine |
| `output_exists` | destination file present (or claimed by an earlier input) |
| `write_failed` | could not write the PNG |
| `bad_arguments` | run-level only: malformed invocation |

### Exit codes

| code | meaning |
|---|---|
| 0 | every image succeeded |
| 1 | some other error (bad arguments, `output_exists`, unreadable input, write failure) |
| 2 | the **only** failures were `no_subject` |
| 3 | a model was missing or would not load |

**Partial-failure batches:** a failing image never aborts the batch. Every input still gets
a record; the exit code summarizes the set, with precedence **3 > 1 > 2**. So a batch of ten
where one image has no subject and nine succeed exits 2 — read the records, not just the
code, to know which files exist.

`pluck models list --json` is a different, simpler shape (one line per engine):

```json
{"id":"birefnet-lite","summary":"BiRefNet_lite via Core ML, 1024px (MIT)","builtIn":false,"installed":true,"updateAvailable":false}
```

`updateAvailable: true` means the app/CLI shipped a newer conversion of an installed
model; `pluck models pull <id> --force` fetches it. Never true for `builtIn`.

## Handling failures

**exit 2 / `no_subject`** — report it as the result. The image has no foreground subject.
Switching models rarely changes this; don't loop.

**exit 3 / `model_missing`** — the message names the fix:

```bash
pluck models pull birefnet-lite
```

Then re-run. `pluck models list` shows what is installed. If the user does not want an
83 MB download, fall back to `--model vision`.

**Interrupted download** — `models pull` resumes. Bytes land in
`~/Library/Application Support/Pluck/Models/.downloads/<id>.partial`, and the next pull
continues from there with a `Range` request. If a process was killed at 60%, just run the
same command again. Integrity is still one SHA-256 over the finished file, so a resume can
never install wrong bytes.

**exit 1 / `output_exists`** — either add `--force`, or pick a different `-o`. Do not
delete the user's file to make room.

## Efficiency

- **Pass every file in one invocation.** `pluck a.jpg b.jpg c.jpg -o out/` runs them
  through an internal concurrent queue; a shell loop over one file at a time is several
  times slower and reloads the model each time.
- Vision is instant and needs no download — it is the right default unless the edges matter.
- First use of a BiRefNet model pays a **one-time Core ML compile of roughly 5–10 seconds**
  (cached in `~/Library/Caches/Pluck/`). Subsequent runs are ~1–2 s per image. Don't read
  the first slow run as a hang.
- Each BiRefNet model is ~83 MB to download, once.

## Verified examples

```bash
# one file, quiet, writes photo.png next to it
pluck photo.jpg

# batch into a directory, machine-readable
pluck shots/*.jpg -o cutouts/ --json

# exact output path, white background
pluck portrait.jpg -o hero.png --background '#ffffff'

# hair and fur
pluck portrait.jpg --model birefnet-lite-matting -o portrait-cut.png

# product shot with hard edges
pluck bottle.jpg --model birefnet-lite -o bottle.png

# pipe, no files touched
cat photo.jpg | pluck - > cut.png

# overwrite an earlier result
pluck photo.jpg --force

# what can this machine run?
pluck models list --json
```
