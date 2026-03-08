#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILDER="${BUILDER:-dee-builder}"
PLATFORM="${PLATFORM:-linux/arm64}"
IMAGE_TAG="${IMAGE_TAG:-dee-box64-lab:local}"
DOCKERFILE="${DOCKERFILE:-$ROOT_DIR/Dockerfile.box64-lab}"
CONTEXT_DIR="${CONTEXT_DIR:-$ROOT_DIR}"
PRUNE_PROFILE="${PRUNE_PROFILE:-conservative}"
GENERATE_ALLOWLIST="${GENERATE_ALLOWLIST:-0}"
ALLOWLIST_MODE="${ALLOWLIST_MODE:-encode}"
BUILD_SLIM="${BUILD_SLIM:-0}"
SLIM_IMAGE_TAG="${SLIM_IMAGE_TAG:-dee-box64-lab:slim-local}"
ARTIFACT_BASE="${ARTIFACT_BASE:-$ROOT_DIR/tmp_box64_prune}"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ARTIFACT_BASE/$RUN_ID}"

usage() {
  cat <<'EOF'
Usage:
  scripts/build_box64_lab.sh [options]

Options:
  --profile NAME          prune profile: conservative|medium|aggressive
  --artifact-dir DIR      output directory for build artifacts
  --generate-allowlist    run runtime file tracing and generate allowlist
  --allowlist-mode MODE   allowlist command mode: help|encode (default: encode)
  --build-slim            build slim image from runtime allowlist
  --slim-tag TAG          slim image tag (default: dee-box64-lab:slim-local)
  -h, --help              show this help

Environment:
  BUILDER, PLATFORM, IMAGE_TAG, DOCKERFILE, CONTEXT_DIR
  PRUNE_PROFILE, GENERATE_ALLOWLIST, ALLOWLIST_MODE
  BUILD_SLIM, SLIM_IMAGE_TAG
  ARTIFACT_BASE, ARTIFACT_DIR
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      shift
      PRUNE_PROFILE="${1:-}"
      ;;
    --artifact-dir)
      shift
      ARTIFACT_DIR="${1:-}"
      ;;
    --generate-allowlist)
      GENERATE_ALLOWLIST=1
      ;;
    --allowlist-mode)
      shift
      ALLOWLIST_MODE="${1:-}"
      ;;
    --build-slim)
      BUILD_SLIM=1
      ;;
    --slim-tag)
      shift
      SLIM_IMAGE_TAG="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$PRUNE_PROFILE" in
  conservative|medium|aggressive) ;;
  *)
    echo "Invalid --profile: $PRUNE_PROFILE (expected conservative|medium|aggressive)" >&2
    exit 2
    ;;
esac

case "$ALLOWLIST_MODE" in
  help|encode) ;;
  *)
    echo "Invalid --allowlist-mode: $ALLOWLIST_MODE (expected help|encode)" >&2
    exit 2
    ;;
esac

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo "Buildx builder '$BUILDER' not found." >&2
  echo "Create it with: docker buildx create --name $BUILDER --driver docker-container --use --bootstrap" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"

capture_pkg_snapshot() {
  local image="$1"
  local out="$2"
  docker run --rm --platform "$PLATFORM" "$image" bash -lc 'dpkg-query -W 2>/dev/null || true' | sort > "$out"
}

PKG_BEFORE="$ARTIFACT_DIR/packages.before.txt"
PKG_AFTER="$ARTIFACT_DIR/packages.after.txt"
PKG_ADDED="$ARTIFACT_DIR/packages.added.txt"
PKG_REMOVED="$ARTIFACT_DIR/packages.removed.txt"
PRUNE_MANIFEST="$ARTIFACT_DIR/prune-manifest.md"

if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "Capturing previous package snapshot from existing image: $IMAGE_TAG"
  capture_pkg_snapshot "$IMAGE_TAG" "$PKG_BEFORE"
else
  : > "$PKG_BEFORE"
fi

echo "Building $IMAGE_TAG using builder '$BUILDER' on platform '$PLATFORM' with profile '$PRUNE_PROFILE'..."
time docker buildx build \
  --builder "$BUILDER" \
  --platform "$PLATFORM" \
  --progress=plain \
  --load \
  --tag "$IMAGE_TAG" \
  --file "$DOCKERFILE" \
  --build-arg PRUNE_PROFILE="$PRUNE_PROFILE" \
  "$CONTEXT_DIR"

echo "Capturing package snapshot from new image: $IMAGE_TAG"
capture_pkg_snapshot "$IMAGE_TAG" "$PKG_AFTER"

cut -d' ' -f1 "$PKG_BEFORE" | sort -u > "$ARTIFACT_DIR/packages.before.names.txt"
cut -d' ' -f1 "$PKG_AFTER" | sort -u > "$ARTIFACT_DIR/packages.after.names.txt"
comm -13 "$ARTIFACT_DIR/packages.before.names.txt" "$ARTIFACT_DIR/packages.after.names.txt" > "$PKG_ADDED"
comm -23 "$ARTIFACT_DIR/packages.before.names.txt" "$ARTIFACT_DIR/packages.after.names.txt" > "$PKG_REMOVED"

{
  echo "# Box64 Prune Manifest"
  echo ""
  echo "- Build time: \`$(date '+%Y-%m-%d %H:%M:%S %z')\`"
  echo "- Image: \`$IMAGE_TAG\`"
  echo "- Platform: \`$PLATFORM\`"
  echo "- Profile: \`$PRUNE_PROFILE\`"
  echo "- Builder: \`$BUILDER\`"
  echo ""
  echo "## Package Snapshot Diff"
  echo ""
  echo "- before lines: \`$(wc -l < "$PKG_BEFORE" | tr -d ' ')\`"
  echo "- after lines: \`$(wc -l < "$PKG_AFTER" | tr -d ' ')\`"
  echo "- added package names: \`$(wc -l < "$PKG_ADDED" | tr -d ' ')\`"
  echo "- removed package names: \`$(wc -l < "$PKG_REMOVED" | tr -d ' ')\`"
  echo ""
  echo "Artifacts:"
  echo "- \`$PKG_BEFORE\`"
  echo "- \`$PKG_AFTER\`"
  echo "- \`$PKG_ADDED\`"
  echo "- \`$PKG_REMOVED\`"
} > "$PRUNE_MANIFEST"

"$ROOT_DIR/scripts/report_box64_image_size.sh" \
  --image "$IMAGE_TAG" \
  --out-dir "$ARTIFACT_DIR"

if [[ "$GENERATE_ALLOWLIST" == "1" ]]; then
  "$ROOT_DIR/scripts/generate_box64_runtime_allowlist.sh" \
    --image "$IMAGE_TAG" \
    --mode "$ALLOWLIST_MODE" \
    --out-dir "$ARTIFACT_DIR"
fi

if [[ "$BUILD_SLIM" == "1" ]]; then
  "$ROOT_DIR/scripts/build_box64_allowlist_slim.sh" \
    --source-image "$IMAGE_TAG" \
    --target-image "$SLIM_IMAGE_TAG" \
    --allowlist "$ARTIFACT_DIR/runtime-allowlist.txt" \
    --artifact-dir "$ARTIFACT_DIR/slim-build"

  "$ROOT_DIR/scripts/report_box64_image_size.sh" \
    --image "$SLIM_IMAGE_TAG" \
    --out-dir "$ARTIFACT_DIR/slim-size-report"
fi

echo "Build complete: $IMAGE_TAG"
echo "Artifacts: $ARTIFACT_DIR"
