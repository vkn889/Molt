#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pinned upstream release, verified against GitHub release asset SHA-256 digests.
for ARCH in arm64 x64; do
  if [[ "$ARCH" == arm64 ]]; then
    HASH=08761eb0d2491ac5320bfd677ea01fa9c39878e61ff44289750be11245126b8f
  else
    HASH=3fa766503cc88d24099b7c36024ac9261de2369b9eab6910be69380816f869a5
  fi
  ARCHIVE="dist/llama-b11236-$ARCH.tar.gz"
  mkdir -p "dist/Runtime/$ARCH"
  curl -fL --retry 2 "https://github.com/ggml-org/llama.cpp/releases/download/b11236/llama-b11236-bin-macos-$ARCH.tar.gz" -o "$ARCHIVE"
  echo "$HASH  $ARCHIVE" | shasum -a 256 -c -
  tar -xzf "$ARCHIVE" --strip-components=1 -C "dist/Runtime/$ARCH"
done
cp docs/licenses/llama.cpp.txt dist/Runtime/LICENSE-llama.cpp.txt
