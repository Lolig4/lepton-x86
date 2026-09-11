#!/bin/bash
set -euo pipefail

# Local test of the tag-list previous-tag lookup used in .gitlab-ci.yml.
# Usage: ./.ci_scripts/test-rootfs-git-describe.sh [TAG] [UPSTREAM] [DEPTH]
#   TAG       defaults to v2.8.2
#   UPSTREAM  defaults to file://$(git rev-parse --show-toplevel)
#   DEPTH     defaults to 1

TAG="${1:-v2.8.2}"
UPSTREAM="${2:-file://$(git rev-parse --show-toplevel)}"
DEPTH="${3:-1}"

echo "=== Cloning $TAG with --depth $DEPTH ==="
echo "Upstream: $UPSTREAM"
echo "Depth: $DEPTH"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone --depth "$DEPTH" --branch "$TAG" "$UPSTREAM" "$tmp/lepton" --quiet
cd "$tmp/lepton"

echo "Shallow checkout: $(git rev-parse --is-shallow-repository 2>/dev/null || echo unknown)"

echo "=== Simulate .gitlab-ci.yml: git fetch --tags ... ==="
git fetch --tags --force --prune origin >/dev/null 2>&1 || true

echo "=== Find previous version tag (new logic) ==="
PREVIOUS_TAG=$(git tag --list 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed -n '/^'"$TAG"'$/{n;p;q}')

if [ -z "$PREVIOUS_TAG" ]; then
  echo "PREVIOUS_TAG not found (would rebuild)"
  exit 1
fi

echo "PREVIOUS_TAG=$PREVIOUS_TAG"

if git diff --quiet "$PREVIOUS_TAG" "$TAG" -- image .ci_scripts/build-rootfs.sh .ci_scripts/install-build-rootfs-dependencies.sh; then
  echo "RESULT: no rootfs changes, would NOT rebuild / would reuse $PREVIOUS_TAG"
else
  echo "RESULT: rootfs changes found, WOULD rebuild"
  exit 1
fi
