#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/StatusBarProbe.app"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
HOST_ARCH="$(uname -m)"

case "$HOST_ARCH" in
  arm64|x86_64)
    ARCH="$HOST_ARCH"
    ;;
  *)
    echo "Unsupported macOS runner architecture: $HOST_ARCH" >&2
    exit 1
    ;;
esac

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR"

xcrun --sdk iphonesimulator clang \
  -fobjc-arc \
  -isysroot "$SDK" \
  -mios-simulator-version-min=15.0 \
  -arch "$ARCH" \
  -framework Foundation \
  -framework UIKit \
  "$ROOT/probe-app/main.m" \
  -o "$APP_DIR/StatusBarProbe"

cp "$ROOT/probe-app/Info.plist" "$APP_DIR/Info.plist"
/usr/bin/codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"

