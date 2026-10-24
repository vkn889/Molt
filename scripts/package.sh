#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.9.2}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo 'Expected a version such as 0.8.0' >&2
  exit 1
fi
# CFBundleVersion must increase with every upload Apple sees; MOLT_BUILD sets it, such as a CI run number.
BUILD="${MOLT_BUILD:-$VERSION}"
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
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleDisplayName</key><string>Molt</string>
<key>CFBundleExecutable</key><string>Molt</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>app.molt.companion</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Molt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>ITSAppUsesNonExemptEncryption</key><false/>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Molt follows and controls Spotify and Apple Music, and runs the shortcuts you choose, such as dark mode (System Events) and emptying the Trash (Finder).</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Molt contributors. MIT License.</string>
<key>NSCalendarsUsageDescription</key><string>Molt reads only the calendars you choose to show upcoming commitments. It never edits events.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Molt reads only selected calendars for your Today dashboard. It never creates or edits events.</string>
<key>NSRemindersUsageDescription</key><string>Molt shows your Reminders in the notch and ticks them off when you do.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>Molt shows your Reminders in the notch, adds the ones you type, and ticks them off when you do.</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>The Quick toggles widget turns Bluetooth on and off when you ask. Molt doesn't connect to or scan for devices.</string>
<key>NSCameraUsageDescription</key><string>The Camera mirror widget shows you to yourself before a call. The picture never leaves your Mac.</string>
</dict></plist>
PLIST
cp scripts/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
# Signing, in order of preference: MOLT_SIGN_IDENTITY, a "Developer ID Application" certificate,
# "Molt Local Signing" (scripts/make-signing-cert.sh), then ad-hoc. Only Developer ID plus
# notarization opens cleanly on other Macs; the others are for this Mac. See docs/distribution.md.
IDENTITY="${MOLT_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Molt Local Signing"'; then
  IDENTITY="Molt Local Signing"
fi
DEVELOPER_ID=0
if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then DEVELOPER_ID=1; fi
if [[ -z "$IDENTITY" ]]; then
  echo "Signing ad-hoc. Run ./scripts/make-signing-cert.sh once so permissions survive updates." >&2
fi
if [[ "$DEVELOPER_ID" == 0 ]]; then
  echo "WARNING: not signed with Developer ID, so Gatekeeper will block this DMG on other Macs." >&2
  if [[ "${MOLT_REQUIRE_NOTARIZATION:-0}" == "1" ]]; then echo "MOLT_REQUIRE_NOTARIZATION=1: stopping." >&2; exit 1; fi
fi
# Hardened runtime everywhere. A secure timestamp is required for notarization and only Apple's
# timestamp server issues one, so local and ad-hoc builds skip it.
SIGN_ARGS=(--force --options runtime --sign "${IDENTITY:--}")
if [[ "$DEVELOPER_ID" == 1 ]]; then SIGN_ARGS+=(--timestamp); else SIGN_ARGS+=(--timestamp=none); fi
# Nested code first, deepest paths first, then the app with its entitlements. --deep is avoided
# for signing because it would give every nested binary the app's entitlements.
while IFS= read -r FILE; do
  if file -b "$FILE" | grep -q 'Mach-O'; then codesign "${SIGN_ARGS[@]}" "$FILE"; fi
done < <(find "$APP/Contents" -type f ! -path "$APP/Contents/MacOS/Molt" -print | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
codesign "${SIGN_ARGS[@]}" --entitlements scripts/Molt.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# Notarization: MOLT_NOTARY_PROFILE names a keychain profile from `xcrun notarytool
# store-credentials`; otherwise an App Store Connect API key from MOLT_NOTARY_KEY (path to the
# .p8), MOLT_NOTARY_KEY_ID and MOLT_NOTARY_ISSUER.
NOTARY_ARGS=()
if [[ -n "${MOLT_NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$MOLT_NOTARY_PROFILE")
elif [[ -n "${MOLT_NOTARY_KEY:-}" && -n "${MOLT_NOTARY_KEY_ID:-}" && -n "${MOLT_NOTARY_ISSUER:-}" ]]; then
  NOTARY_ARGS=(--key "$MOLT_NOTARY_KEY" --key-id "$MOLT_NOTARY_KEY_ID" --issuer "$MOLT_NOTARY_ISSUER")
fi
NOTARIZE=0
if [[ "$DEVELOPER_ID" == 1 && ${#NOTARY_ARGS[@]} -gt 0 ]]; then
  NOTARIZE=1
elif [[ "$DEVELOPER_ID" == 1 ]]; then
  echo "WARNING: Developer ID signed but not notarized. Set MOLT_NOTARY_PROFILE (docs/distribution.md)." >&2
  if [[ "${MOLT_REQUIRE_NOTARIZATION:-0}" == "1" ]]; then echo "MOLT_REQUIRE_NOTARIZATION=1: stopping." >&2; exit 1; fi
fi
notarize() {
  local LOG
  LOG="$(mktemp "$ASSEMBLY/notary.XXXXXX")"
  if ! xcrun notarytool submit "$1" "${NOTARY_ARGS[@]}" --wait --timeout 30m --output-format json > "$LOG"; then
    cat "$LOG" >&2; return 1
  fi
  if ! grep -q '"status" *: *"Accepted"' "$LOG"; then
    cat "$LOG" >&2
    local ID
    ID="$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' "$LOG" | head -1)"
    if [[ -n "$ID" ]]; then xcrun notarytool log "$ID" "${NOTARY_ARGS[@]}" >&2 || true; fi
    return 1
  fi
}
if [[ "$NOTARIZE" == 1 ]]; then
  # The app is stapled on its own so it opens offline after it's copied out of the DMG.
  ditto -c -k --keepParent "$APP" "$ASSEMBLY/Molt-notarize.zip"
  notarize "$ASSEMBLY/Molt-notarize.zip"
  xcrun stapler staple "$APP"
  rm "$ASSEMBLY/Molt-notarize.zip"
fi
if [[ -d dist/Molt.app ]]; then mv dist/Molt.app "$ASSEMBLY/previous-Molt.app"; fi
mv "$APP" dist/Molt.app
APP="dist/Molt.app"
DMG="dist/Molt-$VERSION.dmg"
rm -f "$DMG"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg --volname "Molt" --window-size 560 360 --icon-size 100 --icon 'Molt.app' 140 150 --app-drop-link 420 150 "$DMG" "$APP"
else
  STAGING="$(mktemp -d "${TMPDIR:-/tmp}/molt-dmg.XXXXXX")"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname Molt -srcfolder "$STAGING" -ov -format UDZO "$DMG"
fi
if [[ "$DEVELOPER_ID" == 1 ]]; then codesign --force --timestamp --sign "$IDENTITY" "$DMG"; fi
if [[ "$NOTARIZE" == 1 ]]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  echo "Notarized: $DMG opens without warnings on other Macs."
fi
