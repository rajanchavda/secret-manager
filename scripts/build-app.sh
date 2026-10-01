#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building SecApp with Swift..."
swift build -c release --product SecApp

BIN_SRC=""
if [ -f ".build/out/Products/Release/SecApp" ]; then
    BIN_SRC=".build/out/Products/Release/SecApp"
elif [ -f ".build/release/SecApp" ]; then
    BIN_SRC=".build/release/SecApp"
elif [ -f ".build/arm64-apple-macosx/release/SecApp" ]; then
    BIN_SRC=".build/arm64-apple-macosx/release/SecApp"
fi

if [ -z "$BIN_SRC" ]; then
    echo "❌ Error: Could not locate compiled SecApp binary."
    exit 1
fi

APP_DIR="$SCRIPT_DIR/build/SecApp.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_SRC" "$MACOS_DIR/SecApp"
chmod +x "$MACOS_DIR/SecApp"

if [ -f "$SCRIPT_DIR/Sources/SecApp/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Sources/SecApp/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SecApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.sec.SecApp</string>
    <key>CFBundleName</key>
    <string>Secret Manager</string>
    <key>CFBundleDisplayName</key>
    <string>Secret Manager</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "✍️  Ad-hoc code signing $APP_DIR..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✅ Successfully created $APP_DIR"
echo "👉 Launch with: open build/SecApp.app"
