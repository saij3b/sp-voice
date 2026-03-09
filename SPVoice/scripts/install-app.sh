#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SPVoice.xcodeproj"
SCHEME="SPVoice"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedData"
INSTALL_DIR="$HOME/Applications"

/usr/bin/xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_SOURCE="$(find "$DERIVED_DATA_PATH/Build/Products/Debug" -maxdepth 1 -name '*.app' -print -quit)"

if [[ -z "$APP_SOURCE" ]]; then
  echo "Built app not found in $DERIVED_DATA_PATH/Build/Products/Debug" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
APP_TARGET="$INSTALL_DIR/$(basename "$APP_SOURCE")"
rm -rf "$APP_TARGET"
/usr/bin/ditto "$APP_SOURCE" "$APP_TARGET"

echo "Installed to $APP_TARGET"
open "$APP_TARGET"
