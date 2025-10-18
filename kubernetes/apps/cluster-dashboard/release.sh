#!/bin/bash
set -e

# Cluster Dashboard Release Script
# Usage: ./release.sh [major|minor|patch]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"

# Read current version
CURRENT_VERSION=$(cat "$VERSION_FILE")
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"
PATCH="${VERSION_PARTS[2]}"

# Determine bump type
BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Usage: $0 [major|minor|patch]"
    exit 1
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo "Current version: $CURRENT_VERSION"
echo "New version: $NEW_VERSION"
echo ""

# Confirm
read -p "Create release v$NEW_VERSION? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Update VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"

# Update Chart.yaml
sed -i.bak "s/^version: .*/version: $NEW_VERSION/" "$SCRIPT_DIR/../../charts/cluster-dashboard/Chart.yaml"
sed -i.bak "s/^appVersion: .*/appVersion: \"$NEW_VERSION\"/" "$SCRIPT_DIR/../../charts/cluster-dashboard/Chart.yaml"
rm "$SCRIPT_DIR/../../charts/cluster-dashboard/Chart.yaml.bak"

# Update values.yaml
sed -i.bak "s/tag: \"v[^\"]*\"/tag: \"v$NEW_VERSION\"/" "$SCRIPT_DIR/../../charts/cluster-dashboard/values.yaml"
rm "$SCRIPT_DIR/../../charts/cluster-dashboard/values.yaml.bak"

# Update HelmRelease
sed -i.bak "s/version: \"[^\"]*\"/version: \"$NEW_VERSION\"/" "$SCRIPT_DIR/../../flux/clusters/talos/apps/cluster-dashboard/helmrelease.yaml"
sed -i.bak "s/tag: \"v[^\"]*\"/tag: \"v$NEW_VERSION\"/" "$SCRIPT_DIR/../../flux/clusters/talos/apps/cluster-dashboard/helmrelease.yaml"
rm "$SCRIPT_DIR/../../flux/clusters/talos/apps/cluster-dashboard/helmrelease.yaml.bak"

echo ""
echo "✅ Updated files:"
echo "  - VERSION: $NEW_VERSION"
echo "  - charts/cluster-dashboard/Chart.yaml"
echo "  - charts/cluster-dashboard/values.yaml"
echo "  - flux/clusters/talos/apps/cluster-dashboard/helmrelease.yaml"
echo ""
echo "Next steps:"
echo ""
echo "1. Build and push Docker image:"
echo "   cd kubernetes/apps/cluster-dashboard"
echo "   make docker-push IMAGE_TAG=v$NEW_VERSION"
echo ""
echo "2. Commit changes:"
echo "   git add VERSION charts/ flux/"
echo "   git commit -m \"chore: Release cluster-dashboard v$NEW_VERSION\""
echo ""
echo "3. Create and push git tag:"
echo "   git tag dashboard-v$NEW_VERSION"
echo "   git push origin main --tags"
echo ""
echo "4. GitHub Actions will automatically:"
echo "   - Build and push the Docker image"
echo "   - Create a GitHub release"
echo ""
echo "Or run manually:"
echo "   gh workflow run cluster-dashboard-release.yml -f version=$NEW_VERSION"
