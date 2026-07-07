# Summary

<!-- What & why in 2-3 sentences. -->

## Checklist

- [ ] Builds with the canonical `xcodebuild` command in `AGENTS.md`
- [ ] New/changed stored properties use tolerant decode defaults (`Persistence.swift` rule)
- [ ] Parser changes verified against real PDFs offline (`docs/statements-and-import.md`); no real
      statements, amounts, or account numbers committed (`git ls-files | grep -i pdf` is empty)
- [ ] No secrets committed (`Info.plist` keeps its placeholder; keys live in the Keychain)
- [ ] Reused `Components.swift` / `Theme.swift` (Zen) instead of new one-off UI
- [ ] Docs updated where behaviour changed (`docs/` dev page + `docs/guide/` user page)
