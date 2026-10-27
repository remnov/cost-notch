# Release Cost Notch (Apple Team ID + GitHub)

Current version is `Sources/CostNotch/Info.plist`: `CFBundleShortVersionString` (e.g. `1.1.0`) and `CFBundleVersion` (integer, bump every ship).

Repo: https://github.com/remnov/cost-notch  
This GitHub account is an **Enterprise Managed User** — repos stay **private**. Public OSS needs a personal GitHub user or an org that allows public repos.

## 0. One-time Apple setup

You need a paid Apple Developer account and the **Team ID** (10 characters, Membership details).

### Certificates (Keychain)

In [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) → Certificates → **+**:

1. **Developer ID Application** — signs the `.app` / `.dmg`
2. **Developer ID Installer** — signs the `.pkg`

Create a CSR in Keychain Access (Certificate Assistant → Request a Certificate From a Certificate Authority). Download the certs and double-click to install.

Check:

```bash
security find-identity -v -p codesigning
```

You want lines like:

```
Developer ID Application: Your Name (TEAMID)
Developer ID Installer: Your Name (TEAMID)
```

If that list is empty, Xcode → Settings → Accounts → your Apple ID → Download Manual Profiles, or install the certs from the portal again.

### Notary app-specific password

appleid.apple.com → Sign-In and Security → App-Specific Passwords → generate one.

Store it once:

```bash
xcrun notarytool store-credentials "notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Later commands use `--keychain-profile "notary"` (no password in the shell).

### Optional: stable bundle id

`Info.plist` uses `local.cost-notch`. Fine for notarization. If you want it under your team, change it to reverse-DNS (e.g. `com.yourname.cost-notch`) **before** the first signed release and keep it forever.

## 1. Bump version

Edit `Sources/CostNotch/Info.plist`:

- `CFBundleShortVersionString` → marketing version (`1.2.0`)
- `CFBundleVersion` → build number (`3`, `4`, …)

Commit on `main`.

```bash
git add Sources/CostNotch/Info.plist
git commit -m "Bump version to 1.2.0"
git push origin main
```

## 2. Build, sign, notarize

Set identities (replace with the exact `security find-identity` strings):

```bash
export TEAM_ID="YOURTEAMID"
export APP_SIGN="Developer ID Application: Your Name (${TEAM_ID})"
export PKG_SIGN="Developer ID Installer: Your Name (${TEAM_ID})"
```

### App

```bash
swift test
./build-app.sh
```

`build-app.sh` ad-hoc signs (`-`). Re-sign with Developer ID + hardened runtime:

```bash
APP="artifacts/Cost Notch.app"
[[ -d "$APP" ]] || APP="dist/Cost Notch.app"

codesign --force --deep --options runtime --timestamp \
  --sign "$APP_SIGN" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP" || true
```

`spctl` may fail until notarized. That is expected.

### DMG + PKG

```bash
./package.sh
```

`package.sh` runs `build-app.sh` again (ad-hoc). After it finishes, **re-sign the app**, then rebuild installers **without** letting `build-app.sh` overwrite the signed app — or re-sign after `package.sh` as below.

Simpler path (after `./package.sh`):

```bash
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/CostNotch/Info.plist)"
APP="artifacts/Cost Notch.app"
[[ -d "$APP" ]] || APP="dist/Cost Notch.app"
OUT="dist"
[[ -w dist ]] || OUT="artifacts"

codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN" "$APP"

# DMG: restage signed app
STAGE="${OUT}/package-root"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "${OUT}/Cost-Notch-${VERSION}.dmg"
hdiutil create -volname "Cost Notch" -srcfolder "$STAGE" -ov -format UDZO \
  "${OUT}/Cost-Notch-${VERSION}.dmg"
rm -rf "$STAGE"

codesign --force --timestamp --sign "$APP_SIGN" "${OUT}/Cost-Notch-${VERSION}.dmg"

# PKG: sign installer
UNSIGNED="${OUT}/Cost-Notch-${VERSION}.pkg"
SIGNED="${OUT}/Cost-Notch-${VERSION}-signed.pkg"
productsign --sign "$PKG_SIGN" "$UNSIGNED" "$SIGNED"
mv "$SIGNED" "$UNSIGNED"
```

### Submit to Apple

```bash
xcrun notarytool submit "${OUT}/Cost-Notch-${VERSION}.dmg" \
  --keychain-profile "notary" --wait

xcrun stapler staple "${OUT}/Cost-Notch-${VERSION}.dmg"

xcrun notarytool submit "${OUT}/Cost-Notch-${VERSION}.pkg" \
  --keychain-profile "notary" --wait

xcrun stapler staple "${OUT}/Cost-Notch-${VERSION}.pkg"
```

`status: Accepted` then staple. If **Invalid**, log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "notary"
```

Usual causes: missing `--options runtime`, no `--timestamp`, or unsigned nested binaries.

Confirm:

```bash
spctl --assess --type open --context context:primary-signature -v "${OUT}/Cost-Notch-${VERSION}.dmg"
```

## 3. GitHub release

Logged in as `gh` (`gh auth status`).

```bash
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/CostNotch/Info.plist)"
OUT="dist"
[[ -f "dist/Cost-Notch-${VERSION}.dmg" ]] || OUT="artifacts"

git tag -a "v${VERSION}" -m "Cost Notch ${VERSION}"
git push origin "v${VERSION}"

gh release create "v${VERSION}" \
  "${OUT}/Cost-Notch-${VERSION}.dmg" \
  "${OUT}/Cost-Notch-${VERSION}.pkg" \
  --title "Cost Notch ${VERSION}" \
  --notes "Signed and notarized macOS build.

- **DMG** — open, drag Cost Notch to Applications
- **PKG** — install to /Applications
"
```

To replace an existing tag/release:

```bash
gh release delete "v${VERSION}" --yes
git tag -d "v${VERSION}"
git push origin ":refs/tags/v${VERSION}"
# then create again
```

Do not commit `dist/` or `artifacts/` (gitignored). Only attach them on the GitHub release.

## 4. Checklist

- [ ] Version + build number bumped and pushed
- [ ] `swift test` green
- [ ] App signed with **Developer ID Application** (`--options runtime --timestamp`)
- [ ] DMG signed; PKG signed with **Developer ID Installer**
- [ ] Both notarized (`Accepted`) and stapled
- [ ] `vX.Y.Z` tag pushed
- [ ] GitHub release has `.dmg` and `.pkg`

Other Macs: Gatekeeper should allow a notarized Developer ID build without “Open Anyway”.
