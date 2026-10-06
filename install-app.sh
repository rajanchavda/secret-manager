#!/usr/bin/env bash
# Installs the latest Secret Manager.app from GitHub Releases.
# Files fetched with curl get no quarantine flag, so Gatekeeper does not block the app.
# Usage: curl -fsSL https://raw.githubusercontent.com/rajanchavda/secret-manager/main/install-app.sh | bash
set -euo pipefail

REPO="rajanchavda/secret-manager"
APP="Secret Manager.app"

# /releases/latest redirects to /releases/tag/vX.Y.Z
TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")
TAG="${TAG##*/}"
VERSION="${TAG#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+ ]] || { echo "❌ Could not resolve latest release (got '$TAG')."; exit 1; }

DMG="Secret-Manager-$VERSION.dmg"
BASE="https://github.com/$REPO/releases/download/$TAG"
TMP=$(mktemp -d)
MNT="$TMP/mnt"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "⬇️  Downloading Secret Manager $VERSION..."
curl -fL --progress-bar -o "$TMP/$DMG" "$BASE/$DMG"
curl -fsSL -o "$TMP/$DMG.sha256" "$BASE/$DMG.sha256"

echo "🔐 Verifying SHA256 checksum..."
EXPECTED=$(awk '{print $1}' "$TMP/$DMG.sha256")
ACTUAL=$(shasum -a 256 "$TMP/$DMG" | awk '{print $1}')
[[ "$EXPECTED" == "$ACTUAL" ]] || { echo "❌ Checksum mismatch. Aborting."; exit 1; }

echo "📦 Installing to /Applications..."
hdiutil attach "$TMP/$DMG" -nobrowse -readonly -mountpoint "$MNT" -quiet
pkill -x "Secret Manager" 2>/dev/null || true
SUDO=""; [[ -w /Applications ]] || SUDO="sudo"
$SUDO rm -rf "/Applications/$APP"
$SUDO ditto "$MNT/$APP" "/Applications/$APP"
$SUDO xattr -dr com.apple.quarantine "/Applications/$APP" 2>/dev/null || true

# Link the bundled `sec` CLI, same as the Homebrew cask does
BIN_DIR="/usr/local/bin"
[[ -w "$BIN_DIR" ]] || { BIN_DIR="$HOME/.local/bin"; mkdir -p "$BIN_DIR"; }
ln -sf "/Applications/$APP/Contents/MacOS/sec" "$BIN_DIR/sec"

echo "✅ Installed Secret Manager $VERSION."
echo "   App: /Applications/$APP"
echo "   CLI: $BIN_DIR/sec"
[[ ":$PATH:" == *":$BIN_DIR:"* ]] || echo "   ⚠️  Add $BIN_DIR to your PATH to use 'sec'."
