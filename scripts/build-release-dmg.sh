#!/usr/bin/env bash
set -e

# ==============================================================================
# build-release-dmg.sh
# Builds Secret Manager Universal 2 App Bundle & Packages DMG (No Apple ID needed)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

VERSION="1.0.0"
TARGET_ARCH="universal"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|-v)
            VERSION="$2"
            shift 2
            ;;
        --arch|-a)
            TARGET_ARCH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Strip leading 'v' if passed as v1.2.0
VERSION="${VERSION#v}"

echo "=========================================================="
echo "🚀 Building Secret Manager v${VERSION} (${TARGET_ARCH})"
echo "=========================================================="

BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="Secret Manager"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$BUILD_DIR"

# ------------------------------------------------------------------------------
# 1. Compile Binaries
# ------------------------------------------------------------------------------
compile_product() {
    local product="$1"
    local arch="$2"
    echo "🔨 Compiling ${product} for ${arch}..."
    swift build -c release --arch "$arch" --product "$product"
}

find_binary() {
    local product="$1"
    local arch="$2"
    local candidates=(
        ".build/${arch}-apple-macosx/release/${product}"
        ".build/out/Products/Release/${product}"
        ".build/release/${product}"
    )
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

if [[ "$TARGET_ARCH" == "universal" ]]; then
    echo "📦 Building Universal 2 (arm64 + x86_64)..."
    
    # Try direct universal build first
    if swift build -c release --arch arm64 --arch x86_64 --product SecApp 2>/dev/null && \
       swift build -c release --arch arm64 --arch x86_64 --product sec 2>/dev/null; then
        echo "✓ Built universal binaries directly via SwiftPM."
        SECAPP_BIN=".build/apple/Products/Release/SecApp"
        if [[ ! -f "$SECAPP_BIN" ]]; then
            SECAPP_BIN=$(find .build -name "SecApp" -type f -perm +111 | head -n 1)
        fi
        SEC_CLI_BIN=".build/apple/Products/Release/sec"
        if [[ ! -f "$SEC_CLI_BIN" ]]; then
            SEC_CLI_BIN=$(find .build -name "sec" -type f -perm +111 | grep -v "SecApp" | head -n 1)
        fi
    else
        echo "ℹ️  Building slices individually and linking with lipo..."
        compile_product "SecApp" "arm64"
        compile_product "SecApp" "x86_64"
        compile_product "sec" "arm64"
        compile_product "sec" "x86_64"

        ARM_SECAPP=$(find_binary "SecApp" "arm64")
        INTEL_SECAPP=$(find_binary "SecApp" "x86_64")
        ARM_SEC=$(find_binary "sec" "arm64")
        INTEL_SEC=$(find_binary "sec" "x86_64")

        mkdir -p "$BUILD_DIR/universal"
        SECAPP_BIN="$BUILD_DIR/universal/SecApp"
        SEC_CLI_BIN="$BUILD_DIR/universal/sec"

        lipo -create "$ARM_SECAPP" "$INTEL_SECAPP" -output "$SECAPP_BIN"
        lipo -create "$ARM_SEC" "$INTEL_SEC" -output "$SEC_CLI_BIN"
    fi
else
    compile_product "SecApp" "$TARGET_ARCH"
    compile_product "sec" "$TARGET_ARCH"
    SECAPP_BIN=$(find_binary "SecApp" "$TARGET_ARCH")
    SEC_CLI_BIN=$(find_binary "sec" "$TARGET_ARCH")
fi

echo "✓ SecApp binary: $SECAPP_BIN"
echo "✓ sec CLI binary: $SEC_CLI_BIN"

# ------------------------------------------------------------------------------
# 2. Assemble App Bundle
# ------------------------------------------------------------------------------
echo "📦 Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE" "$BUILD_DIR/SecApp.app"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$SECAPP_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -f "$SEC_CLI_BIN" ]]; then
    echo "📎 Embedding sec CLI inside app bundle..."
    cp "$SEC_CLI_BIN" "$MACOS_DIR/sec"
    chmod +x "$MACOS_DIR/sec"
fi

if [[ -f "$SCRIPT_DIR/Sources/SecApp/Resources/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/Sources/SecApp/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Write Info.plist
cat << EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.sec.SecretManager</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
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

# ------------------------------------------------------------------------------
# 3. Ad-Hoc Code Sign
# ------------------------------------------------------------------------------
echo "✍️  Ad-hoc code signing application..."
if [[ -f "$MACOS_DIR/sec" ]]; then
    codesign --force --sign - "$MACOS_DIR/sec" >/dev/null 2>&1 || true
fi
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

# Verify architecture slice
echo "🔍 Binary architecture:"
file "$MACOS_DIR/$APP_NAME"

# Backward compatibility link
ln -sf "$APP_NAME.app" "$BUILD_DIR/SecApp.app"

# ------------------------------------------------------------------------------
# 4. Create DMG Installer
# ------------------------------------------------------------------------------
DMG_FILENAME="Secret-Manager-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_FILENAME"
DMG_LATEST="$BUILD_DIR/Secret-Manager.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"

echo "💿 Packaging DMG: $DMG_PATH..."
rm -rf "$STAGING_DIR" "$DMG_PATH" "$DMG_LATEST" "${DMG_PATH}.sha256"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$STAGING_DIR" 2>/dev/null || true
    fi
fi

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"
ln -sf "$DMG_FILENAME" "$DMG_LATEST"

# ------------------------------------------------------------------------------
# 5. Checksum & Verification
# ------------------------------------------------------------------------------
echo "🔒 Computing SHA256 checksum..."
(cd "$BUILD_DIR" && shasum -a 256 "$DMG_FILENAME" > "${DMG_FILENAME}.sha256")
(cd "$BUILD_DIR" && shasum -a 256 "$DMG_FILENAME" >> "SHA256SUMS.txt")

hdiutil verify "$DMG_PATH" >/dev/null 2>&1 && echo "✓ DMG integrity verified."

DMG_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
SHA256_HASH=$(awk '{print $1}' "${DMG_PATH}.sha256")

echo ""
echo "=========================================================="
echo "🎉 Release DMG created successfully!"
echo "   Artifact: $DMG_PATH ($DMG_SIZE)"
echo "   SHA256:   $SHA256_HASH"
echo "=========================================================="
