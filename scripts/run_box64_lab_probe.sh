#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-dee-box64-lab:local}"

echo "[1/2] Tooling probe in $IMAGE_TAG"
docker run --rm --platform linux/arm64 "$IMAGE_TAG" bash -lc '
  set -euo pipefail
  command -v box64
  command -v wine64
  dpkg -l | grep -E "^ii\s+(box64|wine64:amd64|libwine:amd64)\s" || true
'

echo "[2/2] Runtime probe in $IMAGE_TAG"
docker run --rm --platform linux/arm64 "$IMAGE_TAG" bash -lc '
  set -euo pipefail
  box64 -v
  box64 /usr/bin/wine64 --version
'

echo "Probe complete."
