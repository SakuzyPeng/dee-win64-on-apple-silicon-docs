#!/usr/bin/env bash
# build_fex_bundled.sh — 构建 FEX bundled 镜像（RootFS 内嵌）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILDER="${BUILDER:-dee-builder}"
IMAGE_TAG="${IMAGE_TAG:-dee-fex-bundled:phase2-balanced-v2}"
DOCKERFILE="${DOCKERFILE:-$ROOT_DIR/Dockerfile.fex-bundled}"
CONTEXT_DIR="${CONTEXT_DIR:-$ROOT_DIR}"
BUNDLED_TRIM_LEVEL="${BUNDLED_TRIM_LEVEL:-balanced}"

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo "Buildx builder '$BUILDER' not found." >&2
  echo "Create it with: docker buildx create --name $BUILDER --driver docker-container --use --bootstrap" >&2
  exit 1
fi

echo "Building $IMAGE_TAG using builder '$BUILDER'..."
echo "Dockerfile: $DOCKERFILE"
echo "BUNDLED_TRIM_LEVEL: $BUNDLED_TRIM_LEVEL"
echo ""
# 多阶段构建同时涉及 linux/amd64（Stage 1）和 linux/arm64（Stage 2）
# buildx 自动处理跨平台 stage，最终 load 的镜像为 arm64
time docker buildx build \
  --builder "$BUILDER" \
  --platform linux/arm64 \
  --progress=plain \
  --load \
  --tag "$IMAGE_TAG" \
  --build-arg "BUNDLED_TRIM_LEVEL=$BUNDLED_TRIM_LEVEL" \
  --file "$DOCKERFILE" \
  "$CONTEXT_DIR"

echo ""
echo "Build complete: $IMAGE_TAG"
echo ""
echo "快速验证："
echo "  DEE_DIR=/path/to/dolby_encoding_engine IMAGE_TAG=$IMAGE_TAG \\"
echo "    ./scripts/run_dee_with_fex_bundled.sh --help"
