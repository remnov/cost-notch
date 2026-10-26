#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building Cost Notch..."
swift build -c release --product CostNotch

OUT="dist"
if [[ -e "dist/Cost Notch.app" && ! -w "dist/Cost Notch.app/Contents" ]]; then
  OUT="artifacts"
fi

if [[ "$OUT" == "dist" ]]; then
  rm -rf dist
fi
rm -rf artifacts

APP_DIR="${OUT}/Cost Notch.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

BIN="$(swift build -c release --show-bin-path)/CostNotch"
cp "$BIN" "$APP_DIR/MacOS/CostNotch"
cp Sources/CostNotch/Info.plist "$APP_DIR/Info.plist"
cp Assets/AppIcon.icns "$APP_DIR/Resources/AppIcon.icns"
codesign --force --sign - "${OUT}/Cost Notch.app" >/dev/null

echo
echo "Built ${OUT}/Cost Notch.app"
echo "Run with: open \"${OUT}/Cost Notch.app\""
