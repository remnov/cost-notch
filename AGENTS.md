# Cost Notch — agent knowledge

macOS 13+ menu-bar + notch overlay for AI spend. Bundle `local.cost-notch`, display name **Cost Notch**, executable `CostNotch`. Cursor is the first provider; Codex / Claude are future sections under the same overlay, not separate apps.

Version lives in `Sources/CostNotch/Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`). Bump both when shipping. `package.sh` reads the short version for DMG/PKG names.

## Layout

- `Sources/CursorCostCore` — session, API, mapping, formatting, `UsageStore`, preferences. Unit-tested.
- `Sources/CostNotch` — AppKit/SwiftUI overlay, menu bar, settings, alerts. No test target.
- `Tests/CursorCostCoreTests` — Swift Testing, given/when/then names.
- `build-app.sh` — release `.app` (ad-hoc signed). Writes `dist/` unless that bundle is not writable, then `artifacts/`.
- `package.sh` — DMG + PKG from whichever `.app` the build just produced.

Do not copy `state.vscdb` (multi-GB, WAL). Do not write tokens back into Cursor’s DB.

## Cursor session (verified 3.27.14)

Path: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (WAL). Open read-only; on failure retry `immutable=1`.

Keys: `cursorAuth/accessToken`, `cursorAuth/refreshToken`, `cursorAuth/cachedEmail` / `cursorAuth/email`.

Cursor 3.27.14 may store tokens as `cursor-safe-storage:v1:` + base64 Electron `v10` ciphertext. `CursorTokenDecoder` uses the **Cursor Safe Storage** service / **Cursor Key** account in macOS Keychain, PBKDF2-HMAC-SHA1 (`saltysalt`, 1003 iterations, 128-bit key), AES-CBC with a 16-space IV and PKCS7 padding. Keep plaintext compatibility. Reject unknown envelope/cipher versions before Keychain access. Decrypt only in memory. Polling disallows Keychain UI; explicit Refresh allows the standard macOS prompt.

After a refresh failure, `.stale` retains the last ready data and error. Compact figures carry `*`, and the expanded overlay/menu shows the stale status. Preserve `lastUpdated` until success. Critical alerts consume only fresh `.ready` snapshots.

Cookie: `WorkosCursorSessionToken={jwt.sub}::{jwt}`. If JWT `exp` is within 60s, refresh in memory:

`POST https://api2.cursor.sh/oauth/token` with `grant_type=refresh_token`, public `client_id` `KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB`. `shouldLogout: true` → session expired. Never persist the new access token.

## Usage APIs

- `GET https://cursor.com/api/usage-summary`
- `POST https://cursor.com/api/dashboard/get-filtered-usage-events` (needs `Origin: https://cursor.com`)

Pool pick (`UsageMapper.pickUsagePool`):

- Team / enterprise (`limitType` team/org or plan name business/team/enterprise/company): `individual.overall` → `team.pooled` → `team.onDemand`. Skip null-limit pools.
- Personal: `onDemand` (only if capped) → `overall` → `plan` only when `usedCents`/`limitCents` exist. Plan `used`/`limit` without those keys are request counts, not dollars.
- `isUnlimited` follows the summary flag, not a missing on-demand cap.

Spend tones: green under cap, red at/over. Percent Current is red at ≥ 100%. `showSpikeWarning` only affects recent-query `!` markers, never Current/Today colors.

## Overlay UX

- Collapsed pill: compact Current on the left of the camera gap. After collapse, snap back to the notched/preferred screen. Non-notch screens are hover-to-show only.
- Expand: pointer on the top ~10px of **any** display, or on the collapsed pill. Panel relocates to that screen.
- Expanded: CURSOR card with Current/Today bars (fill clamped to 100%), recents, Refresh / Dashboard / Settings. `NotchPanel.canBecomeKey` must stay `true` or tray buttons fail.
- Pass hits through expanded shadow gutters (`NotchTrackingView.interactiveInset`).
- Menu extras: compact chips (`currentCompact`, `todayCompact`); full strings in the dropdown. Subscribe to `$snapshot`, not only `objectWillChange`.
- Settings via overlay, menu, or ⌘,. `LSUIElement` — no Dock icon except while Settings/alert is frontmost. Closing Settings must restore `.accessory` unless an alert still needs `.regular`.

## Conventions

Swift, no comments, no inline imports, exhaustive switches with `never`. Reuse existing helpers. Tests: given/when/then names, no duplicate cases, no extra abstractions. Do not add dependencies.

```bash
swift test
./build-app.sh
open "artifacts/Cost Notch.app"   # or dist/
./package.sh                     # Cost-Notch-{version}.dmg + .pkg
```

Signed GitHub releases (Developer ID + notary + `gh release`): **[RELEASE.md](RELEASE.md)**.
