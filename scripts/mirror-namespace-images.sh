#!/usr/bin/env zsh
# mirror-namespace-images.sh
# Pulls all images from pods in a k8s namespace and pushes to a private registry,
# mirroring the exact source path.
set -euo pipefail

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 <namespace>"
  echo "  namespace   Kubernetes namespace to pull images from"
  exit 1
}

[[ $# -lt 1 ]] && usage
NAMESPACE="$1"

# ── Prompt for registry ───────────────────────────────────────────────────────
read "PRIVATE_REGISTRY?Private registry (e.g. registry.internal.example.com): "
PRIVATE_REGISTRY="${PRIVATE_REGISTRY%/}"  # strip trailing slash

if [[ -z "$PRIVATE_REGISTRY" ]]; then
  echo "ERROR: registry cannot be empty" >&2
  exit 1
fi

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in kubectl docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is required but not found in PATH" >&2
    exit 1
  fi
done

# ── Collect unique images from all pods in namespace ─────────────────────────
echo ""
echo "→ Collecting images from namespace: $NAMESPACE"

IMAGES=(${(f)"$(
  kubectl get pods -n "$NAMESPACE" \
    -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u \
  | grep -v '^$'
)"})

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "No images found in namespace '$NAMESPACE'. Are there running pods?"
  exit 0
fi

echo "Found ${#IMAGES[@]} unique image(s):"
for img in "${IMAGES[@]}"; do echo "  $img"; done
echo ""

# ── Pull → Tag → Push ─────────────────────────────────────────────────────────
SUCCESS=()
FAILED=()

for IMAGE in "${IMAGES[@]}"; do
  TARGET="${PRIVATE_REGISTRY}/${IMAGE}"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  SRC:  $IMAGE"
  echo "  DEST: $TARGET"

  if docker pull "$IMAGE" \
    && docker tag "$IMAGE" "$TARGET" \
    && docker push "$TARGET"; then
    SUCCESS+=("$TARGET")
    docker rmi "$IMAGE" "$TARGET" &>/dev/null || true
  else
    echo "  ✗ FAILED: $IMAGE" >&2
    FAILED+=("$IMAGE")
  fi
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Succeeded: ${#SUCCESS[@]}"
for img in "${SUCCESS[@]}"; do echo "  $img"; done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo ""
  echo "✗ Failed: ${#FAILED[@]}"
  for img in "${FAILED[@]}"; do echo "  $img"; done
  exit 1
fi
