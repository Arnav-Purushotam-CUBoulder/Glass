#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Glass"
APP_DIR="$PACKAGE_DIR/build/Glass.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build --package-path "$PACKAGE_DIR" -c release
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)"
swift "$PACKAGE_DIR/BuildSupport/make-icon.swift" "$PACKAGE_DIR/BuildSupport/Glass.icns"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/Glass" "$MACOS_DIR/Glass"
cp "$PACKAGE_DIR/BuildSupport/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PACKAGE_DIR/BuildSupport/Glass.icns" "$RESOURCES_DIR/Glass.icns"

chmod +x "$MACOS_DIR/Glass"

SIGN_IDENTITY="${GLASS_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'\"' '/Apple Development:/{print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'\"' '/Job Triage Local Signing/{print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "$APP_DIR"
