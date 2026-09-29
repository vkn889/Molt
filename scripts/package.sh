#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.4.0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo 'Expected a version such as 0.4.0' >&2
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
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Molt</string>
<key>CFBundleIdentifier</key><string>app.molt.companion</string>
<key>CFBundleName</key><string>Molt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSCalendarsUsageDescription</key><string>Molt reads only the calendars you choose to show upcoming commitments. It never edits events.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Molt reads only selected calendars for your Today dashboard. It never creates or edits events.</string>
</dict></plist>
PLIST
# Runtime is opt-in for development packaging; release workflow prepares it explicitly.
if [[ -d dist/Runtime ]]; then
  cp -R dist/Runtime "$APP/Contents/Resources/Runtime"
  cp docs/licenses/Qwen2.5.txt "$APP/Contents/Resources/Runtime/LICENSE-Qwen2.5.txt"
fi
# Universal binaries need an ad-hoc code signature on Apple Silicon. This is not
# Developer ID signing or notarization and carries no external author identity.
codesign --force --deep --sign - "$APP"
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
