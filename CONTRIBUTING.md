# Contributing

## Setup

macOS 13+, Xcode or Command Line Tools.

```bash
swift test
./build-app.sh
open "artifacts/Cost Notch.app"
```

Read `AGENTS.md` before changing session, usage mapping, or the overlay.

## Pull requests

- Keep diffs small. Reuse helpers in `CursorCostCore` instead of adding types.
- No new dependencies unless the change cannot be done with Foundation / AppKit / SwiftUI.
- Swift: no comments, no inline imports, exhaustive switches with `never`.
- Tests in `Tests/CursorCostCoreTests` use given/when/then names. Do not duplicate cases.
- Do not commit `dist/`, `artifacts/`, `.build/`, or Cursor session files.

`./package.sh` after a version bump in `Sources/CostNotch/Info.plist`.
