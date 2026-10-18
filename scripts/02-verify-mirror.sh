#!/usr/bin/env bash
# Verify all required images are pullable from the mirror registry.
# Run this on the disconnected cluster BEFORE deploying anything.
#
# Usage:
#   export MIRROR_REGISTRY=registry.example.com:5000
#   ./02-verify-mirror.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_FILE="$SCRIPT_DIR/../images.txt"

if [[ -z "${MIRROR_REGISTRY:-}" ]]; then
  echo "ERROR: Set MIRROR_REGISTRY to your disconnected registry"
  exit 1
fi

echo "Verifying images in $MIRROR_REGISTRY"
echo "======================================"

PASS=0
FAIL=0
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  [[ "$line" != podman\ pull\ * ]] && continue

  image="${line#podman pull }"

  dest_path="${image#*/}"
  dest_path="${dest_path//@sha256:/:sha256-}"
  dest="$MIRROR_REGISTRY/$dest_path"

  if skopeo inspect "docker://$dest" &>/dev/null; then
    echo "  OK   $dest"
    PASS=$((PASS + 1))
  else
    echo "  FAIL $dest"
    FAIL=$((FAIL + 1))
  fi
done < "$IMAGES_FILE"

echo ""
echo "======================================"
echo "Passed: $PASS  Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "ERROR: $FAIL image(s) not found. Fix mirroring before proceeding."
  exit 1
else
  echo "All images verified. Safe to proceed with deployment."
fi
