#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILDER="${BUILDER:-dee-builder}"
PLATFORM="${PLATFORM:-linux/arm64}"
IMAGE_TAG="${IMAGE_TAG:-dee-box64-lab:local}"
DOCKERFILE="${DOCKERFILE:-$ROOT_DIR/Dockerfile.box64-lab}"
CONTEXT_DIR="${CONTEXT_DIR:-$ROOT_DIR}"

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo "Buildx builder '$BUILDER' not found." >&2
  echo "Create it with: docker buildx create --name $BUILDER --driver docker-container --use --bootstrap" >&2
  exit 1
fi

echo "Building $IMAGE_TAG using builder '$BUILDER' on platform '$PLATFORM'..."
time docker buildx build \
  --builder "$BUILDER" \
  --platform "$PLATFORM" \
  --progress=plain \
  --load \
  --tag "$IMAGE_TAG" \
  --file "$DOCKERFILE" \
  "$CONTEXT_DIR"

echo "Build complete: $IMAGE_TAG"
