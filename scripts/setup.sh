#!/bin/bash
set -euo pipefail

echo "SP Voice — Developer Setup"
echo "=========================="

# Check Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode not found. Install Xcode from the App Store."
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version | head -1)
echo "✅ $XCODE_VERSION"

# Check Swift
SWIFT_VERSION=$(swift --version 2>&1 | head -1)
echo "✅ $SWIFT_VERSION"

# Check macOS version
MACOS_VERSION=$(sw_vers -productVersion)
echo "✅ macOS $MACOS_VERSION"

MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
    echo "⚠️  macOS 14 (Sonoma) or later is recommended. You have $MACOS_VERSION."
fi

# Open project
echo ""
echo "To open the project:"
echo "  open SPVoice/SPVoice.xcodeproj"
echo ""
echo "Required permissions (grant after first launch):"
echo "  1. Accessibility: System Settings → Privacy & Security → Accessibility"
echo "  2. Microphone: System Settings → Privacy & Security → Microphone"
echo ""
echo "Setup complete."
