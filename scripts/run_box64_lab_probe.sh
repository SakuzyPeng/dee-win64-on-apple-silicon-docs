#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-dee-box64-lab:local}"

echo "[1/2] Tooling probe in $IMAGE_TAG"
docker run --rm --platform linux/arm64 "$IMAGE_TAG" bash -lc '
  set -euo pipefail
  box64_bin="$(command -v box64 || true)"
  if [[ -z "$box64_bin" ]]; then
    echo "box64 not found in PATH" >&2
    exit 127
  fi
  if [[ -x /usr/lib/wine/wine64 ]]; then
    wine_bin=/usr/lib/wine/wine64
  elif [[ -x /usr/bin/wine64 ]]; then
    wine_bin=/usr/bin/wine64
  else
    echo "wine64 binary not found" >&2
    exit 127
  fi
  echo "BOX64_BIN=$box64_bin"
  echo "WINE_BIN=$wine_bin"
  dpkg -l | grep -E "^ii\s+(wine64:amd64|libwine:amd64)\s" || true
'

echo "[2/2] Runtime probe in $IMAGE_TAG"
docker run --rm --platform linux/arm64 "$IMAGE_TAG" bash -lc '
  set -euo pipefail
  box64_bin="$(command -v box64)"
  if [[ -x /usr/lib/wine/wine64 ]]; then
    wine_bin=/usr/lib/wine/wine64
  else
    wine_bin=/usr/bin/wine64
  fi
  "$box64_bin" -v
  "$box64_bin" "$wine_bin" --version
'

echo "Probe complete."
