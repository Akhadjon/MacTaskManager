#!/usr/bin/env bash
# package_app.sh — builds MacTaskManager and packages it as dist/MacTaskManager.app

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST="$PROJECT_ROOT/dist"
APP="$DIST/MacTaskManager.app"

echo "==> Building MacTaskManager (release)…"
cd "$PROJECT_ROOT"
swift build -c release 2>&1

BINARY="$(swift build -c release --show-bin-path 2>/dev/null)/MacTaskManager"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: binary not found at $BINARY" >&2
    exit 1
fi

echo "==> Assembling app bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP/Contents/MacOS/MacTaskManager"
chmod +x "$APP/Contents/MacOS/MacTaskManager"

# Write Info.plist
cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.mactaskmanager.app</string>
    <key>CFBundleName</key>
    <string>MacTaskManager</string>
    <key>CFBundleDisplayName</key>
    <string>MacTaskManager</string>
    <key>CFBundleExecutable</key>
    <string>MacTaskManager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MacTaskManager</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Done. App bundle: $APP"
echo "    Run with: open $APP"
echo "    Or double-click in Finder."
