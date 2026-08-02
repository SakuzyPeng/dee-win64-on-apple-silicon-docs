#!/usr/bin/env bash
# Verify the public diagnostics toolbox and DME-required Wine payload.
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-dee-fex-bundled:phase2-balanced-v6}"
PLATFORM="${PLATFORM:-linux/arm64}"

if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--image" && $# -eq 2 ]]; then
    IMAGE_TAG="$2"
  else
    echo "Usage: scripts/check_fex_bundled_payload.sh [--image TAG]" >&2
    exit 2
  fi
fi

echo "Checking bundled payload: $IMAGE_TAG"

docker run --rm -i --platform "$PLATFORM" "$IMAGE_TAG" bash -s <<'INNER'
set -euo pipefail

rootfs=/root/.fex-emu/RootFS/Ubuntu_24_04
required_tools=(
  curl
  file
  jq
  lsof
  mediainfo
  objdump
  patchelf
  python3
  rg
  strace
  strings
  unzip
  xxd
  xz
  zstd
)

for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null
done

test -f "$rootfs/usr/lib/wine/wine64"
test -f "$rootfs/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/avrt.dll"
FEX /usr/lib/wine/wine64 --version
mediainfo --Version | sed -n '1p'
python3 --version
echo "PAYLOAD_CHECK_PASS"
INNER
