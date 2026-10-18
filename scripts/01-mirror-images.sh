#!/usr/bin/env bash
# Mirror all required images to a disconnected registry.
#
# Usage:
#   export MIRROR_REGISTRY=registry.example.com:5000
#   ./01-mirror-images.sh
#
# Requires: skopeo (or podman/docker)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_FILE="$SCRIPT_DIR/../images.txt"

if [[ -z "${MIRROR_REGISTRY:-}" ]]; then
  echo "ERROR: Set MIRROR_REGISTRY to your disconnected registry (e.g. registry.example.com:5000)"
  exit 1
fi

if ! command -v skopeo &>/dev/null; then
  echo "ERROR: skopeo is required. Install it first."
  exit 1
fi

echo "Mirroring images from images.txt to $MIRROR_REGISTRY"
echo "======================================================"

FAILED=0
while IFS= read -r line; do
  # Skip empty lines, comments, and non-podman lines
  [[ -z "$line" || "$line" == \#* ]] && continue
  [[ "$line" != podman\ pull\ * ]] && continue

  # Extract the image reference after "podman pull "
  image="${line#podman pull }"

  # Derive the destination path: strip the source registry, keep repo + tag
  dest_path="${image#*/}"
  # Handle @sha256 digests -- convert to a tag-like path
  dest_path="${dest_path//@sha256:/:sha256-}"
  dest="$MIRROR_REGISTRY/$dest_path"

  echo ""
  echo "--- Mirroring: $image"
  echo "    To:        $dest"

  if skopeo copy --all "docker://$image" "docker://$dest"; then
    echo "    OK"
  else
    echo "    FAILED"
    FAILED=$((FAILED + 1))
  fi
done < "$IMAGES_FILE"

echo ""
echo "======================================================"
if [[ $FAILED -gt 0 ]]; then
  echo "WARNING: $FAILED image(s) failed to mirror."
  exit 1
else
  echo "All images mirrored successfully."
fi
