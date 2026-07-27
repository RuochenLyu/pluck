# Pluck

**Lift subjects out of photos. Offline, free, open source.**

Pluck is a native macOS app (and CLI) that removes image backgrounds entirely on-device.
Your photos never leave your Mac — no account, no upload, no subscription, no watermark.

> 🚧 Early development. Nothing to install yet — see [docs/product-plan.md](docs/product-plan.md) for where this is going.

## Why another background remover?

- **100% offline.** Powered by Apple's on-device Vision framework by default; optional
  higher-quality Core ML models (MIT-licensed) downloaded on demand. Auditable — it's all here.
- **Native, fast, zero-config.** Menu bar drag & drop, Finder right-click, a clipboard
  round-trip (⌘C → hotkey → ⌘V), batch processing with progress.
- **Built for AI agents too.** The same engine ships as a `pluck` CLI with `--json` output
  and an agent skill — the first background remover designed to be driven by agents.
- **Free forever.** No "HD behind a paywall", no weekly subscription.

## Planned architecture

`PluckKit` (Swift library, the only engine) → thin shells: SwiftUI app, `pluck` CLI,
Finder Quick Action. Requires macOS 14+.

## Docs

- [Product plan](docs/product-plan.md) · [Research](docs/research.md) · [Decisions](docs/decisions.md)
- Agents: start at [AGENTS.md](AGENTS.md)

## License

MIT
