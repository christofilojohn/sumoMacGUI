#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0-alpha}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/XcodeDerivedData-Release"
RELEASE_DIR="$ROOT_DIR/.build/releases"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/SumoGUIMac.app"
ZIP_PATH="$RELEASE_DIR/SumoGUIMac-$VERSION-macOS-arm64.zip"

mkdir -p "$RELEASE_DIR"

xcodebuild \
  -project "$ROOT_DIR/SumoGUIMac.xcodeproj" \
  -scheme SumoGUIMacApp \
  -configuration "$CONFIGURATION" \
  -destination platform=macOS \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle was not produced at: $APP_PATH" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$APP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Built app: $APP_PATH"
echo "Release zip: $ZIP_PATH"
