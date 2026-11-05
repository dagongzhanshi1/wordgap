#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_APP="${WORDGAP_APP_PATH:-$TASK_ROOT/dist/词隙.app}"
TASK_BUILD="${WORDGAP_BUILD_PATH:-$TASK_ROOT/.build}"
TASK_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
TASK_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
if [ ! -x "$TASK_SWIFTC" ]; then
    TASK_SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
    TASK_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
fi
mkdir -p "$TASK_BUILD" "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
"$TASK_SWIFTC" -swift-version 5 -O -sdk "$TASK_SDK" -target arm64-apple-macosx13.0 \
    -framework AppKit -framework SwiftUI -framework Combine -framework Carbon -framework Charts -framework QuartzCore -framework Security -framework ApplicationServices \
    "$TASK_ROOT"/Sources/*.swift -o "$TASK_BUILD/WordGap"
cp "$TASK_BUILD/WordGap" "$TASK_APP/Contents/MacOS/WordGap"
cp "$TASK_ROOT"/Resources/*.json "$TASK_ROOT"/Resources/*.txt "$TASK_APP/Contents/Resources/"
cp "$TASK_ROOT"/Resources/*.wav "$TASK_APP/Contents/Resources/"
cp "$TASK_ROOT/Info.plist" "$TASK_APP/Contents/Info.plist"
if [ ! -f "$TASK_APP/Contents/Resources/AppIcon.icns" ] || [ "$TASK_ROOT/scripts/icon.swift" -nt "$TASK_APP/Contents/Resources/AppIcon.icns" ]; then
    "$TASK_SWIFTC" -sdk "$TASK_SDK" "$TASK_ROOT/scripts/icon.swift" -o "$TASK_BUILD/icon-maker"
    "$TASK_BUILD/icon-maker" "$TASK_BUILD/AppIcon.iconset"
    /usr/bin/iconutil -c icns "$TASK_BUILD/AppIcon.iconset" -o "$TASK_APP/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --sign - "$TASK_APP"
echo "BUILD_OK: $TASK_APP"
