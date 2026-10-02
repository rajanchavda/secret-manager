#!/usr/bin/env bash
set -e

# ==============================================================================
# tag.sh - Single command to create/recreate and push release tags
# Usage: ./scripts/tag.sh v1.0.0
# ==============================================================================

TAG="$1"

if [ -z "$TAG" ]; then
    echo "❌ Error: No tag specified."
    echo "Usage: ./scripts/tag.sh <version-tag>"
    echo "Example: ./scripts/tag.sh v1.0.0"
    exit 1
fi

# Ensure tag starts with 'v'
if [[ ! "$TAG" =~ ^v ]]; then
    TAG="v$TAG"
fi

echo "🏷️  Recreating and pushing tag: $TAG..."

# Delete local tag if it exists
git tag -d "$TAG" 2>/dev/null || true

# Delete remote tag if it exists
git push origin :refs/tags/"$TAG" 2>/dev/null || true

# Create tag on latest commit
git tag "$TAG"

# Push tag to GitHub
git push origin "$TAG"

echo ""
echo "✅ Tag $TAG pushed successfully to GitHub!"
echo "🚀 GitHub Actions release workflow has been triggered."
