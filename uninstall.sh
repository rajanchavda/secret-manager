#!/usr/bin/env bash
set -e

# ==============================================================================
# uninstall.sh
# Uninstalls sec CLI, Finder Quick Actions, and optional vault storage
# ==============================================================================

PURGE_DATA=false
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --purge|--all)
            PURGE_DATA=true
            ;;
        --yes|-y|-f|--force)
            FORCE=true
            ;;
        --help|-h)
            echo "Usage: ./uninstall.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --purge, --all    Also remove ~/.sec (deletes master key, registry, and backups)"
            echo "  --yes, -y         Skip interactive confirmation"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
    esac
done

echo "🗑️  Uninstalling sec (macOS Touch ID Secrets Vault)..."
echo ""

# 1. Remove CLI binary / symlink
REMOVED_CLI=0
PATHS_TO_CHECK=(
    "/usr/local/bin/sec"
    "$HOME/.local/bin/sec"
    "/opt/homebrew/bin/sec"
)

for bin_path in "${PATHS_TO_CHECK[@]}"; do
    if [ -f "$bin_path" ] || [ -L "$bin_path" ]; then
        echo "Removing CLI executable: $bin_path"
        if [ -w "$(dirname "$bin_path")" ] || [ -w "$bin_path" ]; then
            rm -f "$bin_path"
            REMOVED_CLI=1
        else
            echo "  Requires sudo to remove $bin_path..."
            sudo rm -f "$bin_path"
            REMOVED_CLI=1
        fi
    fi
done

if [ "$REMOVED_CLI" -eq 1 ]; then
    echo "✅ Removed sec CLI binary."
else
    echo "ℹ️  No sec binary found in standard PATH directories."
fi

# 2. Remove macOS Finder Quick Actions
SERVICES_DIR="$HOME/Library/Services"
WORKFLOWS=(
    "Lock Secrets with Touch ID (sec).workflow"
    "Unlock Secrets with Touch ID (sec).workflow"
    "Edit Secrets with Touch ID (sec).workflow"
    "View Secrets with Touch ID (sec).workflow"
)

REMOVED_WORKFLOWS=0
for wf in "${WORKFLOWS[@]}"; do
    target="$SERVICES_DIR/$wf"
    if [ -d "$target" ]; then
        echo "Removing Finder Quick Action: $wf"
        rm -rf "$target"
        REMOVED_WORKFLOWS=1
    fi
done

if [ "$REMOVED_WORKFLOWS" -eq 1 ]; then
    # Flush macOS Services cache
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
    touch "$SERVICES_DIR" 2>/dev/null || true
    killall ServicesUIAgent 2>/dev/null || true
    echo "✅ Removed Finder Quick Actions."
fi

# 3. Handle ~/.sec Data & Master Key
SEC_DIR="$HOME/.sec"
if [ -d "$SEC_DIR" ]; then
    echo ""
    if [ "$PURGE_DATA" = true ]; then
        echo "⚠️  Purging all configuration and master encryption keys in $SEC_DIR..."
        rm -rf "$SEC_DIR"
        echo "✅ Erased $SEC_DIR."
    else
        echo "ℹ️  Preserved '$SEC_DIR' (contains your Secure Enclave master token and backups)."
        echo "   If you still have locked .vault files on your disk, keep this directory to decrypt them."
        echo "   To purge data and master keys completely, run:"
        echo "     rm -rf ~/.sec"
    fi
fi

# 4. Check for macOS Desktop App
if [ -d "/Applications/Secret Manager.app" ]; then
    echo ""
    echo "📱 Desktop App Notice:"
    echo "   'Secret Manager.app' is still in /Applications."
    if command -v brew >/dev/null 2>&1 && brew list --cask secret-manager >/dev/null 2>&1; then
        echo "   To completely remove the Homebrew Cask:"
        echo "     brew uninstall --cask secret-manager"
    else
        echo "   To remove it, drag /Applications/Secret Manager.app to Trash or run:"
        echo "     rm -rf \"/Applications/Secret Manager.app\""
    fi
fi

echo ""
echo "=================================================================="
echo "🎉 sec CLI uninstallation complete!"
echo "=================================================================="
