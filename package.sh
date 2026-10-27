#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/CostNotch/Info.plist)"
IDENTIFIER="local.cost-notch"
APP_NAME="Cost Notch"

./build-app.sh

APP_SRC=""
if [[ -d "artifacts/${APP_NAME}.app" ]]; then
  APP_SRC="artifacts/${APP_NAME}.app"
elif [[ -d "dist/${APP_NAME}.app" ]]; then
  APP_SRC="dist/${APP_NAME}.app"
else
  echo "No ${APP_NAME}.app found in artifacts/ or dist/" >&2
  exit 1
fi

OUT="dist"
if [[ -e dist && ! -w dist ]]; then
  OUT="artifacts"
fi
mkdir -p "$OUT"

STAGE="${OUT}/package-root"
DMG="${OUT}/Cost-Notch-${VERSION}.dmg"
PKG="${OUT}/Cost-Notch-${VERSION}.pkg"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_SRC" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$PKG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

pkgbuild \
  --install-location /Applications \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --component "$APP_SRC" \
  "$PKG" >/dev/null

rm -rf "$STAGE"

echo
echo "App:                  $APP_SRC"
echo "Installer disk image: $DMG"
echo "Installer package:    $PKG"
echo
echo "Open the DMG and drag Cost Notch into Applications."
echo "Or install the PKG: open \"$PKG\""
