#!/bin/bash
set -euo pipefail

# SP Voice build-and-install script.
# Signs with "SP Voice Dev" cert so TCC grants persist across rebuilds.
# Does NOT reset TCC — permissions are permanent once granted.

APP="/Users/a1/Applications/SP Voice.app"
BINARY="$APP/Contents/MacOS/SP Voice"
ENTITLEMENTS="/tmp/sp-voice/SPVoice/SPVoice/SPVoice.entitlements"
SRC="/tmp/sp-voice/SPVoice"

echo "==> Killing SP Voice if running..."
pkill -x "SP Voice" 2>/dev/null || true
sleep 1

echo "==> Compiling..."
cd "$SRC"
xcrun --sdk macosx swiftc \
  -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -enable-bare-slash-regex \
  -framework Cocoa \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework Carbon \
  -framework ApplicationServices \
  -framework Security \
  $(find SPVoice -name '*.swift' | sort) \
  -o /tmp/sp-voice-binary 2>&1 | grep -v warning || true

echo "==> Installing binary..."
cp /tmp/sp-voice-binary "$BINARY"

echo "==> Signing bundle with SP Voice Dev cert..."
codesign -s "SP Voice Dev" -f \
  --identifier "com.spvoice.app" \
  --entitlements "$ENTITLEMENTS" \
  "$APP"

echo "==> Launching..."
open "$APP"

echo "==> Done! Settings, API key, hotkey, and permissions are all preserved."
