#!/usr/bin/env bash
#
# release.sh — Build all platform binaries and publish them as a GitHub release.
#
# Builds via scripts/build.sh, then creates a release on the target repo with
# the tarballs + the curl installer attached. The git tag is created at the
# current branch's pushed HEAD, so push the branch first.
#
# Requirements: gh (brew install gh) authenticated via `gh auth login`.
#
# Usage:
#   scripts/release.sh [version]      # version defaults to cli/package.json
# Env:
#   SANDBOX_RELEASE_REPO=owner/repo   # defaults to the 'origin' remote
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/cli"
DIST="$CLI/dist"

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found — install with: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated — run: gh auth login"; exit 1; }

REPO="${SANDBOX_RELEASE_REPO:-$(git -C "$ROOT" remote get-url origin \
  | sed -E 's#^(https://|git@)([^@/]+@)?github\.com[:/]##; s#\.git$##')}"
VERSION="${1:-$(node -p "require('$CLI/package.json').version")}"
TAG="v$VERSION"
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"

echo "==> Repo:    $REPO"
echo "==> Tag:     $TAG  (from branch $BRANCH)"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "error: release $TAG already exists on $REPO"; exit 1
fi

# Build artifacts
"$ROOT/scripts/build.sh"

# Attach the curl installer too, if present (matches the CI release)
EXTRA=()
[ -f "$CLI/bin/install.sh" ] && EXTRA+=("$CLI/bin/install.sh")

echo "==> Creating release $TAG on $REPO"
gh release create "$TAG" \
  --repo "$REPO" \
  --target "$BRANCH" \
  --title "$TAG" \
  --generate-notes \
  "$DIST"/*.tar.gz "${EXTRA[@]}"

echo "==> Published: https://github.com/$REPO/releases/tag/$TAG"
