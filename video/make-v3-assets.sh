#!/bin/zsh
# Assets for the version 3 commercial that aren't kept in git: the Dock's app icons (from this
# Mac) and the 3D MacBook (from the 16-inch MacBook Pro model zip, converted with Blender).
# Usage: ./make-v3-assets.sh path/to/macbook-pro-m3-16-inch-2024.zip
set -e
cd "${0:A:h}"
mkdir -p public/v3/dock
for app in /System/Library/CoreServices/Finder.app /Applications/Safari.app /System/Applications/{Messages,Mail,Maps,Photos,FaceTime,Notes,Reminders,Music,"App Store","System Settings"}.app /System/Applications/Utilities/Terminal.app; do
  icon=$(defaults read "$app/Contents/Info" CFBundleIconFile 2>/dev/null || echo AppIcon)
  sips -s format png -Z 128 "$app/Contents/Resources/${icon%.icns}.icns" --out "public/v3/dock/$(basename "$app" .app | tr -d ' ').png" >/dev/null
done
sips -Z 128 public/ad/app-icon.png --out public/v3/dock/Molt.png >/dev/null
model=$(mktemp -d)
unzip -q "$1" -d "$model"
/Applications/Blender.app/Contents/MacOS/Blender -b "$model"/source/*.blend --python make-macbook.py -- "$PWD/public/v3/macbook.glb"
rm -r "$model"
node render-screens.mjs
