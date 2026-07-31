#!/bin/bash
# Build ClaudeBubble.app from main.swift — no Xcode project needed.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/ClaudeBubble.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 \
  -framework SwiftUI -framework AppKit -framework Combine -framework Carbon \
  "$DIR/main.swift" -o "$APP/Contents/MacOS/ClaudeBubble"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeBubble</string>
  <key>CFBundleDisplayName</key><string>Claude Bubble</string>
  <key>CFBundleIdentifier</key><string>com.pensaer.claudebubble</string>
  <key>CFBundleExecutable</key><string>ClaudeBubble</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleShortVersionString</key><string>0.4</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will run it locally.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
