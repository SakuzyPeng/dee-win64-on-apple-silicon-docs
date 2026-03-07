#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILDER="${BUILDER:-dee-builder}"
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE_TAG="${IMAGE_TAG:-dee-wine-minimal:local}"
DOCKERFILE="${DOCKERFILE:-$ROOT_DIR/Dockerfile.minimal-wine}"
CONTEXT_DIR="${CONTEXT_DIR:-$ROOT_DIR}"
CACHE_DIR="${CACHE_DIR:-$ROOT_DIR/.buildx-cache}"
CACHE_NEW_DIR="${CACHE_NEW_DIR:-$ROOT_DIR/.buildx-cache-new}"

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo "Buildx builder '$BUILDER' not found." >&2
  echo "Create it with: docker buildx create --name $BUILDER --driver docker-container --use --bootstrap" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$CACHE_NEW_DIR"

echo "Building $IMAGE_TAG using builder '$BUILDER' on platform '$PLATFORM'..."
time docker buildx build \
  --builder "$BUILDER" \
  --platform "$PLATFORM" \
  --progress=plain \
  --load \
  --tag "$IMAGE_TAG" \
  --file "$DOCKERFILE" \
  --cache-from "type=local,src=$CACHE_DIR" \
  --cache-to "type=local,dest=$CACHE_NEW_DIR,mode=max" \
  "$CONTEXT_DIR"

rm -rf "$CACHE_DIR"
mv "$CACHE_NEW_DIR" "$CACHE_DIR"

echo "Build complete: $IMAGE_TAG"
