#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-dee-fex-lab:local}"
ROOTFS_BASE="${ROOTFS_BASE:-$ROOT_DIR/tmp_fex_rootfs}"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOTFS_BASE/RootFS/Ubuntu_24_04}"

echo "[1/2] Base probe in $IMAGE_TAG"
docker run --rm --platform linux/arm64 "$IMAGE_TAG" bash -lc '
  set -euo pipefail
  command -v FEX
  command -v FEXBash
  command -v FEXRootFSFetcher
  ls -l /usr/lib/wine/aarch64-windows/libarm64ecfex.dll \
        /usr/lib/wine/aarch64-windows/libwow64fex.dll
'

if [[ ! -d "$ROOTFS_DIR" ]]; then
  echo "[2/2] Skipped FEXBash probe: extracted RootFS not found at $ROOTFS_DIR" >&2
  echo "Hint: extract tmp_fex_rootfs/RootFS/Ubuntu_24_04.sqsh to that directory first." >&2
  exit 0
fi

echo "[2/2] FEXBash probe with extracted RootFS"
docker run --rm --platform linux/arm64 \
  -v "$ROOTFS_BASE:/root/.fex-emu" \
  "$IMAGE_TAG" bash -lc '
    set -euo pipefail
    export FEX_ROOTFS=/root/.fex-emu/RootFS/Ubuntu_24_04
    FEXBash -c "getconf LONG_BIT; uname -m"
  '
