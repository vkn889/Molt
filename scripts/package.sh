#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.9.2}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo 'Expected a version such as 0.8.0' >&2
  exit 1
fi
BUILD_ARGS=(-c release)
if [[ "${MOLT_UNIVERSAL:-1}" == "1" ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p dist
ASSEMBLY="$(mktemp -d "dist/.assembly.XXXXXX")"
APP="$ASSEMBLY/Molt.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Molt" "$APP/Contents/MacOS/Molt"
# SPM resolves resources beside the executable or in the bundle resource directory.
for RESOURCE in "$BIN_DIR"/*.bundle; do
  if [[ -d "$RESOURCE" ]]; then cp -R "$RESOURCE" "$APP/Contents/Resources/"; fi
done
# The app icon is drawn by Molt itself from the same pixel grid as the creature.
ICONSET="$ASSEMBLY/AppIcon.iconset"
"$BIN_DIR/Molt" --render-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Molt</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>app.molt.companion</string>
<key>CFBundleName</key><string>Molt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Molt follows and controls Spotify and Apple Music, and runs the shortcuts you choose, such as dark mode (System Events) and emptying the Trash (Finder).</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCalendarsUsageDescription</key><string>Molt reads only the calendars you choose to show upcoming commitments. It never edits events.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Molt reads only selected calendars for your Today dashboard. It never creates or edits events.</string>
<key>NSRemindersUsageDescription</key><string>Molt shows your Reminders in the notch and ticks them off when you do.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>Molt shows your Reminders in the notch, adds the ones you type, and ticks them off when you do.</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>The Quick toggles widget turns Bluetooth on and off when you ask. Molt doesn't connect to or scan for devices.</string>
<key>NSCameraUsageDescription</key><string>The Camera mirror widget shows you to yourself before a call. The picture never leaves your Mac.</string>
</dict></plist>
PLIST
# Signs with "Molt Local Signing" when it exists (scripts/make-signing-cert.sh), so macOS keeps
# permissions like Screen Recording across updates; otherwise ad-hoc, which macOS treats as a new
# app every build. MOLT_SIGN_IDENTITY overrides. Neither is Developer ID signing or notarization.
IDENTITY="${MOLT_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Molt Local Signing"'; then
  IDENTITY="Molt Local Signing"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "Signing ad-hoc. Run ./scripts/make-signing-cert.sh once so permissions survive updates." >&2
fi
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
if [[ -d dist/Molt.app ]]; then mv dist/Molt.app "$ASSEMBLY/previous-Molt.app"; fi
mv "$APP" dist/Molt.app
APP="dist/Molt.app"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg --volname "Molt" --window-size 560 360 --icon-size 100 --icon 'Molt.app' 140 150 --app-drop-link 420 150 "dist/Molt-$VERSION.dmg" "$APP"
else
  STAGING="$(mktemp -d "${TMPDIR:-/tmp}/molt-dmg.XXXXXX")"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname Molt -srcfolder "$STAGING" -ov -format UDZO "dist/Molt-$VERSION.dmg"
fi
