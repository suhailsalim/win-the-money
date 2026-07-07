---
name: wtm-build
description: Build Win the Money for the iOS simulator and triage the output. Use for any "build it", "does it compile", or post-edit verification step in this repo.
---

# Build & verify Win the Money

Run exactly this (paths contain spaces — keep the quoting):

```bash
cd "/Users/suhailaka/win the money" && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project WinTheMoney.xcodeproj -scheme WinTheMoney \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$(cat /tmp/wtm_sim.txt)" \
  -derivedDataPath build/dd -allowProvisioningUpdates build 2>&1 \
  | grep -iE "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

- If `/tmp/wtm_sim.txt` is missing/stale: `xcrun simctl list devices booted` → write a booted UDID to
  it; if none booted, use `-destination 'platform=iOS Simulator,name=iPhone 16 Pro'` instead.
- Free personal team `WNU93FA79R`, bundle `com.suhail.WinTheMoney` — signing errors about iCloud/
  entitlements usually mean a capability the free team lacks, not broken code.
- There is **no test target**. Parser changes are verified with the offline harness (see the
  `wtm-parser` skill / `tools/parser-harness/` if present), not XCTest.
- To launch after building:
  `xcrun simctl install <udid> build/dd/Build/Products/Debug-iphonesimulator/WinTheMoney.app && xcrun simctl launch <udid> com.suhail.WinTheMoney`
- Ignore benign console noise: `nw_protocol_… udp`, `CoreGraphics PDF has logged an error`,
  `<decode: bad range …>`.
- Widgets target: `WinTheMoneyWidgets` builds with the app scheme; entitlement changes must be applied
  to both targets.

After a failed build, fix and log the root cause to `.wolf/buglog.json` (OpenWolf rule).
