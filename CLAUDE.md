# CLAUDE.md

Entry point for Claude Code / AI agents. **Read [`AGENTS.md`](AGENTS.md) first** — it has the build
command, architecture, file map, conventions, and gotchas. Per-feature detail is in [`docs/`](docs/).

## TL;DR

- SwiftUI / iOS 26 personal-finance app. **On-device only, no backend, no third-party deps.**
- `Store.swift` is the single source of truth; persistence is **tolerant Codable** — when adding a stored
  property, give it a decode default (see `Persistence.swift` / [`docs/persistence-and-backup.md`](docs/persistence-and-backup.md)).
- Build: the `xcodebuild … -allowProvisioningUpdates` command in [`AGENTS.md`](AGENTS.md). No test target;
  verify parsers with the offline PDFKit harness ([`docs/statements-and-import.md`](docs/statements-and-import.md)).
- Don't commit secrets (`Info.plist` ships a placeholder client id; secrets go in the Keychain).
- Ignore benign console noise: `nw_protocol_… udp`, `CoreGraphics PDF … error`, `<decode: bad range …>`.

## OpenWolf

This project uses [OpenWolf](https://openwolf.com) (Claude Code middleware: project map + learned
conventions + token-aware reads). `.wolf/` is git-ignored — run `openwolf init` locally. Honour the
"Do-Not-Repeat" notes in `.wolf/cerebrum.md`.
