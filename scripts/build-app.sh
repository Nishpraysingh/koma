#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
bundle="$PWD/dist/Koma.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_directory/MihonMac" "$bundle/Contents/MacOS/Koma"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
    iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$bundle"
ditto -c -k --keepParent --norsrc "$bundle" "$PWD/dist/Koma.zip"
echo "Built $bundle"
