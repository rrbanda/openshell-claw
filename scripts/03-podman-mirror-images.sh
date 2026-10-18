#!/usr/bin/env bash
# Pull all images and push them to an internal mirror registry using podman.
#
# This is the podman alternative to 01-mirror-images.sh (which uses skopeo).
# Use this when skopeo is not available.
#
# Run on a CONNECTED machine that can reach both the public registries
# and your internal mirror.
#
# Usage:
#   export MIRROR_REGISTRY=registry.example.com:5000
#   ./03-podman-mirror-images.sh
#
# If your mirror needs auth:
#   podman login $MIRROR_REGISTRY
#
# If pulling Red Hat images:
#   podman login registry.redhat.io
#
# After this script completes, all images are in your mirror.
# Then apply the ImageDigestMirrorSet on your disconnected cluster:
#   sed 's|PLACEHOLDER_MIRROR|registry.example.com:5000|g' \
#     00-prerequisites/imagedigestmirrorset.yaml | oc apply -f -
set -euo pipefail

if [[ -z "${MIRROR_REGISTRY:-}" ]]; then
  echo "ERROR: Set MIRROR_REGISTRY to your internal registry."
  echo "  Example: export MIRROR_REGISTRY=registry.example.com:5000"
  exit 1
fi

echo "============================================================"
echo "Pulling and pushing all OpenShell images to $MIRROR_REGISTRY"
echo "============================================================"

# Image map: SOURCE -> MIRROR_PATH
# Format: "source_image|mirror_path_under_registry"
IMAGES=(
  "ghcr.io/nvidia/openshell/gateway@sha256:7fb31ce604ce5fef58f481fda815f7ed710a9ca18d1262b700bd63114607fb60|nvidia/openshell/gateway:0.1.3"
  "ghcr.io/nvidia/openshell/supervisor@sha256:1da55431d1b36e71ac881a93edd5b6743d179faf9b008a31963d2c3db50637a9|nvidia/openshell/supervisor:0.1.3"
  "ghcr.io/nvidia/openshell/sandbox@sha256:2658534bfb3f1ebba4bb7792e9e875a0972edbe7ae5f58d807ae22c46844a2ac|nvidia/openshell/sandbox:0.1.3"
  "nvcr.io/nvidia/base/ubuntu@sha256:fdfe3e69644d4c52ccdf2195413d1037e17b0b2bc8ff000806c548cafdc686b6|nvidia/base/ubuntu:24.04"
  "quay.io/opendatahub/odh-openshell-sandbox-openclaw@sha256:b977255e7ee9a8e3cea95bc8ba3ad08a93c5e9ad335984e2db1282b80eb82441|opendatahub/odh-openshell-sandbox-openclaw:2026.9.5"
  "quay.io/gkrumbach07/openshell-dashboard@sha256:7118fca976b75f6f3de196785ed4f689a089ccd898ac283e595f712d5bd2f176|gkrumbach07/openshell-dashboard:0.1.1"
  "quay.io/oauth2-proxy/oauth2-proxy@sha256:7c25fd50e1998798b79d051bd7d98ebac8dc4c6c1e54c99f4cb06f3e7d117dbd|oauth2-proxy/oauth2-proxy:v7.15.2"
  "registry.k8s.io/agent-sandbox/agent-sandbox-controller@sha256:c33439351fcb5e6b85fed69e9b81e7fa1a7d8d5fce1e311f6b4086ca6bcf3502|agent-sandbox/agent-sandbox-controller:v0.5.0"
)

TOTAL=${#IMAGES[@]}
PASSED=0
FAILED=0

for entry in "${IMAGES[@]}"; do
  SOURCE="${entry%%|*}"
  DEST_PATH="${entry##*|}"
  DEST="$MIRROR_REGISTRY/$DEST_PATH"

  echo ""
  echo "--- [$((PASSED + FAILED + 1))/$TOTAL] ---"
  echo "  Pull:  $SOURCE"
  echo "  Tag:   $DEST"
  echo "  Push:  $DEST"

  if ! podman pull "$SOURCE"; then
    echo "  FAILED to pull"
    FAILED=$((FAILED + 1))
    continue
  fi

  if ! podman tag "$SOURCE" "$DEST"; then
    echo "  FAILED to tag"
    FAILED=$((FAILED + 1))
    continue
  fi

  if ! podman push "$DEST"; then
    echo "  FAILED to push"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "  OK"
  PASSED=$((PASSED + 1))
done

echo ""
echo "============================================================"
echo "Results: $PASSED passed, $FAILED failed (out of $TOTAL)"
echo "============================================================"

if [[ $FAILED -gt 0 ]]; then
  echo "WARNING: $FAILED image(s) failed. Fix and re-run."
  exit 1
else
  echo ""
  echo "All images mirrored to $MIRROR_REGISTRY."
  echo ""
  echo "Next steps on your disconnected OpenShift cluster:"
  echo "  1. Apply the ImageDigestMirrorSet:"
  echo "     sed 's|PLACEHOLDER_MIRROR|$MIRROR_REGISTRY|g' \\"
  echo "       00-prerequisites/imagedigestmirrorset.yaml | oc apply -f -"
  echo ""
  echo "  2. Verify images are pullable:"
  echo "     export MIRROR_REGISTRY=$MIRROR_REGISTRY"
  echo "     ./scripts/02-verify-mirror.sh"
fi
