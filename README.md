# Pluck

**Lift subjects out of photos. Offline, free, open source.**

Pluck is a native macOS app (and CLI) that removes image backgrounds entirely on-device.
Your photos never leave your Mac — no account, no upload, no subscription, no watermark.

> 🚧 In development. It builds and runs from source today (`swift build`,
> `./Scripts/bundle.sh`), but there is no packaged download and will not be one
> before 1.0 — we don't ship half-finished tools.

## Why another background remover?

- **100% offline.** Apple's on-device Vision framework by default; optional higher-quality
  BiRefNet models (MIT-licensed, [published here](https://github.com/RuochenLyu/pluck/releases/tag/models-v1))
  downloaded on demand and verified against pinned SHA256 digests. Auditable — it's all here.
- **Native and zero-config.** Menu-bar shelf with drag & drop and ⌘V, batch window with
  progress, history that survives relaunches. A Finder Quick Action is planned.
- **Built for AI agents too.** The same engine ships as a `pluck` CLI: `--json` NDJSON
  output, semantic exit codes, no GUI, no TTY assumptions.
- **Free forever.** No "HD behind a paywall", no weekly subscription.

## Architecture

`PluckKit` (Swift library, the only engine) → thin shells: SwiftUI menu-bar app and the
`pluck` CLI. Vision runs built-in; BiRefNet variants run through Core ML after an explicit
`pluck models pull <id>` (or a click in Settings). Requires macOS 14+.

```bash
swift build            # library + CLI
swift test             # the whole suite, no network needed
./Scripts/bundle.sh    # a runnable Pluck.app in .build/
```

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
