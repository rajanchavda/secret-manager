#!/usr/bin/env bash
set -e

echo "🔒 Installing sec (macOS Touch ID Secrets Vault)..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Build release binary
echo "🔨 Building release binary with Swift..."
swift build -c release

# Find release binary location
BIN_SRC=""
if [ -f ".build/out/Products/Release/sec" ]; then
    BIN_SRC=".build/out/Products/Release/sec"
elif [ -f ".build/release/sec" ]; then
    BIN_SRC=".build/release/sec"
elif [ -f ".build/arm64-apple-macosx/release/sec" ]; then
    BIN_SRC=".build/arm64-apple-macosx/release/sec"
fi

if [ -z "$BIN_SRC" ]; then
    echo "❌ Error: Could not locate compiled release binary."
    exit 1
fi

# 2. Determine installation target
INSTALL_DIR="/usr/local/bin"
if [ ! -w "$INSTALL_DIR" ]; then
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
fi

echo "📦 Installing binary to $INSTALL_DIR/sec..."
cp "$BIN_SRC" "$INSTALL_DIR/sec"
chmod +x "$INSTALL_DIR/sec"

# 3. Install Finder Quick Actions
echo "🖱️  Registering macOS Finder Quick Actions..."
"$INSTALL_DIR/sec" install-finder

echo ""
echo "=================================================================="
echo "🎉 sec successfully installed to $INSTALL_DIR/sec!"
echo "=================================================================="
echo ""
echo "🚀 Quick Start:"
echo "   1. Lock your .env file:"
echo "      $ sec lock .env"
echo ""
echo "   2. Run development commands with secrets injected in memory:"
echo "      $ sec npm run dev"
echo "      $ sec pnpm dev"
echo "      $ sec cargo run"
echo ""
echo "   3. Edit secrets safely with Touch ID:"
echo "      $ sec edit .env"
echo ""
echo "   4. In Finder: Right-click any file -> Quick Actions / Services -> 'Lock/Unlock Secrets with Touch ID'"
echo ""

# Check PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠️  Note: $INSTALL_DIR is not in your PATH."
    echo "   Add it by adding this to your ~/.zshrc or ~/.bashrc:"
    echo "   export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
fi
