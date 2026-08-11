# Pluck

**Lift subjects out of photos. Offline, free, open source.**

English · [简体中文](README.zh-Hans.md)

Pluck is a native macOS app (and CLI) that removes image backgrounds entirely on-device.
Your photos never leave your Mac — no account, no upload, no subscription, no watermark.

> 🚧 In development. It builds and runs from source today (`swift build`,
> `./Scripts/bundle.sh`), but there is no packaged download and will not be one
> before 1.0 — we don't ship half-finished tools.

## Why another background remover?

- **Offline by default.** Apple's on-device Vision framework; optional higher-quality
  BiRefNet models (MIT-licensed, [published here](https://github.com/RuochenLyu/pluck/releases/tag/models-v1))
  downloaded on demand and verified against pinned SHA256 digests. Auditable — it's all here.
- **Engines that disagree usefully.** Vision is instant and honest about "no subject";
  BiRefNet Clean Cut rescues line art and reaches *into* a photographed painting where
  Vision lifts the framed object; Fine Edges renders glass actually transparent. Measured,
  not marketed — see the [audit](docs/research.md).
- **Native and zero-config.** One standard window: drag images in (or ⌘V straight from
  the clipboard), compare before/after side by side, switch engines per image, export the
  batch. Grid and list views, history that survives relaunches. A Finder Quick Action is
  planned.
- **Built for AI agents too.** The same engine ships as a `pluck` CLI: `--json` NDJSON
  output, semantic exit codes, no GUI, no TTY assumptions.
- **Free forever.** No "HD behind a paywall", no weekly subscription.

## Architecture

`PluckKit` (Swift library, the only engine) → thin shells: a SwiftUI app and the
`pluck` CLI. Vision runs built-in; BiRefNet variants run through Core ML after an explicit
`pluck models pull <id>` (or a click in Settings). Model updates arrive with app updates
and are compared locally against install receipts — checking costs no network request.
Requires macOS 26+.

```bash
swift build            # library + CLI
swift test             # the whole suite, no network needed
./Scripts/bundle.sh    # a runnable Pluck.app in .build/
```

## What talks to the network

Your images never do. Matting runs entirely on this Mac, and there is no account, no
telemetry and no upload path in the app at all. Two things do connect, both listed here
because a privacy claim is worth exactly what its exceptions are worth:

| What | When | Turn it off |
|---|---|---|
| **Model download** | Only when you click Download in Settings ▸ Models, or run `pluck models pull`. Fetches a BiRefNet package from this repo's GitHub Releases and checks it against a SHA256 digest pinned in [`models/manifest.json`](models/manifest.json). | Never happens unless you ask. |
| **Update check** | Once a day, the app asks GitHub whether a newer version exists. Nothing about you or your images is sent. Updates are signed with EdDSA and verified before installation ([Sparkle](https://sparkle-project.org)). | Settings ▸ General ▸ *Check for updates automatically*. Off means Pluck makes no request of its own, ever. |

The `pluck` CLI never checks for updates — the only network call it can make is an explicit
`models pull`.

## Use with AI agents

Pluck ships an agent skill in [`skills/pluck/`](skills/pluck/SKILL.md). Install it by
copying or symlinking the directory:

```bash
ln -s "$PWD/skills/pluck" ~/.claude/skills/pluck    # or: cp -r skills/pluck ~/.claude/skills/
```

The agent then drives the same CLI you would:

```bash
pluck shots/*.jpg -o cutouts/ --json     # NDJSON per image on stdout
pluck photo.jpg --model birefnet-lite-matting -o cut.png
```

[SKILL.md](skills/pluck/SKILL.md) documents the full `--json` contract, the `error` slugs
and the exit codes (0 ok · 1 error · 2 no subject · 3 model problem).

## Docs

- [Product plan](docs/product-plan.md) · [Roadmap](docs/roadmap.md) · [Research](docs/research.md) · [Decisions](docs/decisions.md)
- Agents: start at [AGENTS.md](AGENTS.md)

## License

MIT. Bundled model conversions remain under their upstream MIT license with attribution —
see the NOTICE inside each [model asset](https://github.com/RuochenLyu/pluck/releases/tag/models-v1).
