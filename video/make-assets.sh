#!/bin/bash
# Renders Molt's animation loops and the cropped notch screenshots the video uses, from the app itself.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
B=.build/debug/Molt
P=video/public/molt
R() { "$B" --render-creature "$P/$1" --size 300 --fps 30 "${@:2}" >/dev/null; }
R happy --mood happy --frames 60; R celebrate --mood celebrating --frames 90; R idle --mood idle --frames 120
R work-claude --mood working --shell claude --frames 60; R work-codex --mood working --shell codex --frames 60
R work-gemini --mood working --shell gemini --frames 60; R alert --mood alert --frames 60; R love --mood love --frames 60
R worried --mood worried --frames 60; R tired --mood tired --frames 60; R sleep --mood sleeping --frames 90
for fit in pumpkin,scarf headphones,shades hardhat,bowtie halo,cape beanie,glasses santa,scarf bunny,backpack; do
  R "fit-${fit%%,*}" --mood waving --outfit "$fit" --frames 30
done
for shot in agents usage github wardrobe chat; do
  ffmpeg -v error -y -i "docs/screenshots/notch-$shot.png" -vf "crop=1440:418:108:0" "video/public/crop-notch-$shot.png"
done
ffmpeg -v error -y -i docs/screenshots/notch-approval.png -vf "crop=1224:274:216:0" video/public/crop-notch-approval.png
ffmpeg -v error -y -i docs/screenshots/notch-finished.png -vf "crop=1224:180:216:0" video/public/crop-notch-finished.png
