#!/usr/bin/env bash
# check_fex_bundled_cold_start.sh
# Strict cold-start check for FEX bundled image:
# 1) reset WINEPREFIX
# 2) run wineboot with visible logs
# 3) run dee.exe --help
# 4) fail on configured critical signatures
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-dee-fex-bundled:phase2-balanced-v3}"
DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_fex_bundled_state_coldcheck}"
WINEPREFIX="${WINEPREFIX:-/state/WinePrefixes/cold_fex_bundled}"
WINEBOOT_TIMEOUT="${WINEBOOT_TIMEOUT:-120}"
HELP_TIMEOUT="${HELP_TIMEOUT:-60}"
WINE_BIN="${WINE_BIN:-/usr/lib/wine/wine64}"
DEE_WIN_EXE="${DEE_WIN_EXE:-y:/dolby_encoding_engine/dee.exe}"
STRICT_FAIL_REGEX="${STRICT_FAIL_REGEX:-Library ntoskrnl\\.exe .*not found|service L\"Winedevice[0-9]+\" failed to start|Importing dlls for .*winedevice\\.exe failed}"

usage() {
  cat <<'EOF'
Usage:
  scripts/check_fex_bundled_cold_start.sh [options]

Options:
  --image TAG            bundled image tag
  --dee-dir DIR          host dolby_encoding_engine directory
  --state-dir DIR        state directory mounted to /state
  --wineprefix PATH      wine prefix path in container (must start with /state/)
  --wineboot-timeout N   wineboot timeout seconds (default: 120)
  --help-timeout N       dee --help timeout seconds (default: 60)
  -h, --help             show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) shift; IMAGE_TAG="${1:-}" ;;
    --dee-dir) shift; DEE_DIR="${1:-}" ;;
    --state-dir) shift; STATE_DIR="${1:-}" ;;
    --wineprefix) shift; WINEPREFIX="${1:-}" ;;
    --wineboot-timeout) shift; WINEBOOT_TIMEOUT="${1:-}" ;;
    --help-timeout) shift; HELP_TIMEOUT="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! -d "$DEE_DIR" ]]; then
  echo "DEE directory not found: $DEE_DIR" >&2
  exit 1
fi

if [[ ! -f "$DEE_DIR/dee.exe" ]]; then
  echo "dee.exe not found: $DEE_DIR/dee.exe" >&2
  exit 1
fi

if [[ ! "$WINEPREFIX" =~ ^/state/ ]]; then
  echo "--wineprefix must start with /state/: $WINEPREFIX" >&2
  exit 2
fi

mkdir -p "$STATE_DIR"
host_prefix_path="$STATE_DIR/${WINEPREFIX#/state/}"
rm -rf "$host_prefix_path"

echo "Cold-start check image: $IMAGE_TAG"
echo "Cold-start WINEPREFIX: $WINEPREFIX"
echo "Cold-start host prefix: $host_prefix_path"

docker run --rm -i --platform linux/arm64 \
  -e WINEPREFIX="$WINEPREFIX" \
  -e WINEBOOT_TIMEOUT="$WINEBOOT_TIMEOUT" \
  -e HELP_TIMEOUT="$HELP_TIMEOUT" \
  -e STRICT_FAIL_REGEX="$STRICT_FAIL_REGEX" \
  -e WINE_BIN="$WINE_BIN" \
  -e DEE_WIN_EXE="$DEE_WIN_EXE" \
  -v "$STATE_DIR:/state" \
  -v "$ROOT_DIR:/workspace" \
  -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
  "$IMAGE_TAG" \
  bash -s <<'INNER'
set -euo pipefail

FEX_ROOTFS_IN_IMAGE="/root/.fex-emu/RootFS/Ubuntu_24_04"

mkdir -p "$WINEPREFIX/drive_c" "$WINEPREFIX/dosdevices"
ln -sfn ../drive_c "$WINEPREFIX/dosdevices/c:"
ln -sfn "$FEX_ROOTFS_IN_IMAGE" "$WINEPREFIX/dosdevices/z:"
ln -sfn /workspace "$WINEPREFIX/dosdevices/y:"

echo "STEP:wineboot"
set +e
timeout "$WINEBOOT_TIMEOUT" \
  FEX /bin/bash -lc "WINEPREFIX=$WINEPREFIX WINEDEBUG=fixme-all $WINE_BIN wineboot.exe -u" \
  > /tmp/cold_wineboot.log 2>&1
wb_rc=$?
set -e
echo "WINEBOOT_RC:$wb_rc"
sed -n '1,120p' /tmp/cold_wineboot.log

if [[ "$wb_rc" -ne 0 ]]; then
  echo "Cold-start fail: wineboot returned $wb_rc" >&2
  exit 11
fi

if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_wineboot.log; then
  echo "Cold-start fail: critical signature detected in wineboot log" >&2
  exit 12
fi

echo "STEP:help"
set +e
timeout "$HELP_TIMEOUT" \
  FEX /bin/bash -lc "WINEPREFIX=$WINEPREFIX WINEDEBUG=fixme-all $WINE_BIN $DEE_WIN_EXE --help" \
  > /tmp/cold_help.log 2>&1
help_rc=$?
set -e
echo "HELP_RC:$help_rc"
sed -n '1,120p' /tmp/cold_help.log

if [[ "$help_rc" -ne 0 ]]; then
  echo "Cold-start fail: dee --help returned $help_rc" >&2
  exit 13
fi

if ! grep -q "dee.exe, Version" /tmp/cold_help.log; then
  echo "Cold-start fail: help signature not found" >&2
  exit 14
fi

if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_help.log; then
  echo "Cold-start fail: critical signature detected in help log" >&2
  exit 15
fi

echo "COLD_START_PASS"
INNER
