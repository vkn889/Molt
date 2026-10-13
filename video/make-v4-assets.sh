#!/bin/bash
# Builds what version 4 and the teaser need, then renders them without glitches.
# Expects in ~/Downloads: macbook-pro-14-inch-m5.zip, macbook.zip, musicNONCOPYRIGHT.mp3 and the
# boom (alexis_gaming_cam-cinematic-bass-boom-free-370400.mp3). Run from video/ after make-v3-assets.sh.
set -euo pipefail
cd "$(dirname "$0")"
D=~/Downloads
T=$(mktemp -d)
B=/Applications/Blender.app/Contents/MacOS/Blender

# The teaser: glasses on, walking, the ominous score and the boom.
P=public/molt; R() { ../.build/debug/Molt --render-creature "$P/$1" --size 300 --fps 30 "${@:2}" >/dev/null; }
R glasses-idle --mood idle --outfit glasses --frames 300; R glasses-walk --mood idle --walking --outfit glasses --frames 120
mkdir -p public/teaser public/v4/audio public/v4/clips
python3 -I make-chiptune.py public/teaser/chiptune.wav 15.4
cp "$D/alexis_gaming_cam-cinematic-bass-boom-free-370400.mp3" public/teaser/boom.mp3
iconutil -c iconset ../dist/Molt.app/Contents/Resources/AppIcon.icns -o "$T/icon.iconset"
cp "$T/icon.iconset/icon_512x512@2x.png" public/teaser/app-icon.png

# Version 4: the two hero Macs, the song, the woosh and space, and every 3D screen.
unzip -oq "$D/macbook-pro-14-inch-m5.zip" -d "$T/m5"; unzip -oq "$D/macbook.zip" -d "$T/mac"
"$B" -b --python make-hero-macs.py -- "$T/m5/source/macbook_pro_14_inch_M5.glb" "$T/mac/source/Mac Laptop.fbx" public/v4 >/dev/null
cp "$D/musicNONCOPYRIGHT.mp3" public/v4/audio/music.mp3
python3 -I make-v4-sfx.py public/v4/audio
node render-screens.mjs

# The 3D shots on the GPU, then the trailer and the teaser in software; every frame is checked.
for c in V4HeroA:hero-a V4HeroB:hero-b V4Grid:grid; do CRF=12 node render-safe.mjs "${c%%:*}" "public/v4/clips/${c##*:}.mp4" --gl=angle --audio=none; done
node render-safe.mjs MoltAdV4 out/Molt-Commercial-v4.mp4
node render-safe.mjs Teaser out/Molt-Teaser-v2.mp4
rm -rf "$T"
