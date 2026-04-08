#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeStat"
APP_BUNDLE="$HOME/Applications/${APP_NAME}.app"

echo "▶ Building ${APP_NAME}..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

BINARY=".build/release/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
  echo "✗ Build failed — binary not found"
  exit 1
fi

echo "▶ Creating .app bundle at ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

# Copy icon if present
if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
  cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeStat</string>
    <key>CFBundleIdentifier</key>
    <string>com.lance.claudestat</string>
    <key>CFBundleName</key>
    <string>ClaudeStat</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc code signing (required for stable launch on macOS 13+)
echo "▶ Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1

echo "✓ Built and signed: ${APP_BUNDLE}"
echo ""
echo "To launch:"
echo "  open \"${APP_BUNDLE}\""
echo ""
echo "To add to Login Items:"
echo "  System Settings → General → Login Items → add ClaudeStat"
