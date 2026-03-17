#!/usr/bin/env bash
# check_route_cold_start_matrix.sh
# Unified strict cold-start matrix for bundled / box64 / fex-lab / legacy routes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/tmp_route_cold_matrix/$RUN_ID}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_route_cold_state}"
DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
FEX_ROOTFS_BASE="${FEX_ROOTFS_BASE:-$ROOT_DIR/tmp_fex_rootfs}"

STRICT_FAIL_REGEX="${STRICT_FAIL_REGEX:-Library ntoskrnl\\.exe .*not found|service L\"Winedevice[0-9]+\" failed to start|Importing dlls for .*winedevice\\.exe failed}"
INCLUDE_LEGACY="${INCLUDE_LEGACY:-1}"

BUNDLED_IMAGES_DEFAULT=(
  "dee-fex-bundled:phase2-balanced"
  "ghcr.io/sakuzypeng/dee-fex-bundled:phase2-balanced"
)
BOX64_IMAGES_DEFAULT=(
  "dee-box64-lab:local"
  "dee-box64-lab:slim-local"
  "dee-box64-lab:slim-help-local"
  "ghcr.io/sakuzypeng/dee-box64-lab:latest"
  "ghcr.io/sakuzypeng/dee-box64-lab:slim-latest"
)
FEX_LAB_IMAGES_DEFAULT=(
  "ghcr.io/sakuzypeng/dee-fex-lab:latest"
)
LEGACY_IMAGES_DEFAULT=(
  "ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest"
)

usage() {
  cat <<'EOF'
Usage:
  scripts/check_route_cold_start_matrix.sh [options]

Options:
  --out-dir DIR         output directory for summary/logs
  --state-dir DIR       host state directory root
  --dee-dir DIR         host dolby_encoding_engine directory
  --fex-rootfs-base DIR host tmp_fex_rootfs base (for fex-lab route)
  --strict-regex REGEX  critical signature regex
  --with-legacy         include legacy route (default)
  --without-legacy      skip legacy route
  -h, --help            show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      shift
      OUT_DIR="${1:-}"
      ;;
    --state-dir)
      shift
      STATE_DIR="${1:-}"
      ;;
    --dee-dir)
      shift
      DEE_DIR="${1:-}"
      ;;
    --fex-rootfs-base)
      shift
      FEX_ROOTFS_BASE="${1:-}"
      ;;
    --strict-regex)
      shift
      STRICT_FAIL_REGEX="${1:-}"
      ;;
    --with-legacy)
      INCLUDE_LEGACY="1"
      ;;
    --without-legacy)
      INCLUDE_LEGACY="0"
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

if [[ ! -d "$DEE_DIR" || ! -f "$DEE_DIR/dee.exe" ]]; then
  echo "DEE directory invalid: $DEE_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$STATE_DIR"
SUMMARY_TSV="$OUT_DIR/summary.tsv"
printf "route\timage\trc\tresult\tcritical_sig_count\treason\tlog\n" > "$SUMMARY_TSV"

image_exists() {
  local image="$1"
  docker image inspect "$image" >/dev/null 2>&1
}

log_name_for() {
  local route="$1"
  local image="$2"
  local safe
  safe="$(echo "$image" | sed 's#[/:@]#_#g')"
  echo "$OUT_DIR/${route}_${safe}.log"
}

append_row() {
  local route="$1"
  local image="$2"
  local rc="$3"
  local result="$4"
  local critical="$5"
  local reason="$6"
  local log="$7"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$route" "$image" "$rc" "$result" "$critical" "$reason" "$log" \
    >> "$SUMMARY_TSV"
}

run_bundled_check() {
  local image="$1"
  local route_state="$STATE_DIR/bundled"
  local prefix="/state/WinePrefixes/cold_bundled"
  rm -rf "$route_state/${prefix#/state/}" || true
  mkdir -p "$route_state"

  IMAGE_TAG="$image" \
  DEE_DIR="$DEE_DIR" \
  STATE_DIR="$route_state" \
  WINEPREFIX="$prefix" \
  STRICT_FAIL_REGEX="$STRICT_FAIL_REGEX" \
    "$ROOT_DIR/scripts/check_fex_bundled_cold_start.sh"
}

run_box64_check() {
  local image="$1"
  local route_state="$STATE_DIR/box64"
  local prefix="/state/WinePrefixes/cold_box64"
  rm -rf "$route_state/${prefix#/state/}" || true
  mkdir -p "$route_state"

  docker run --rm --platform linux/arm64 \
    -e WINEPREFIX="$prefix" \
    -e STRICT_FAIL_REGEX="$STRICT_FAIL_REGEX" \
    -v "$route_state:/state" \
    -v "$ROOT_DIR:/workspace" \
    -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
    "$image" \
    bash -s <<'INNER'
set -euo pipefail

if [[ -x /usr/local/bin/box64 ]]; then
  box64_bin=/usr/local/bin/box64
elif [[ -x /usr/bin/box64 ]]; then
  box64_bin=/usr/bin/box64
else
  echo "FAIL: box64 binary not found" >&2
  exit 127
fi

if [[ -x /usr/lib/wine/wine64 ]]; then
  wine_bin=/usr/lib/wine/wine64
elif [[ -x /usr/bin/wine64 ]]; then
  wine_bin=/usr/bin/wine64
else
  echo "FAIL: wine64 binary not found" >&2
  exit 127
fi

mkdir -p "$WINEPREFIX/drive_c" "$WINEPREFIX/dosdevices"
ln -sfn ../drive_c "$WINEPREFIX/dosdevices/c:"
ln -sfn / "$WINEPREFIX/dosdevices/z:"
ln -sfn /workspace "$WINEPREFIX/dosdevices/y:"

set +e
timeout 120 "$box64_bin" "$wine_bin" wineboot.exe -u > /tmp/cold_wineboot.log 2>&1
wb_rc=$?
set -e
if [[ "$wb_rc" -ne 0 ]]; then
  echo "FAIL: wineboot rc=$wb_rc" >&2
  sed -n '1,120p' /tmp/cold_wineboot.log
  exit 11
fi
if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_wineboot.log; then
  echo "FAIL: critical signature in wineboot log" >&2
  sed -n '1,120p' /tmp/cold_wineboot.log
  exit 12
fi

set +e
timeout 90 "$box64_bin" "$wine_bin" y:/dolby_encoding_engine/dee.exe --help > /tmp/cold_help.log 2>&1
help_rc=$?
set -e
if [[ "$help_rc" -ne 0 ]]; then
  echo "FAIL: help rc=$help_rc" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 13
fi
if ! grep -q "dee.exe, Version" /tmp/cold_help.log; then
  echo "FAIL: help signature missing" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 14
fi
if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_help.log; then
  echo "FAIL: critical signature in help log" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 15
fi

echo "PASS: box64 cold-start"
INNER
}

run_fex_lab_check() {
  local image="$1"
  local route_state="$STATE_DIR/fex_lab"
  local prefix="/state/WinePrefixes/cold_fex_lab"
  rm -rf "$route_state/${prefix#/state/}" || true
  mkdir -p "$route_state"

  docker run --rm --platform linux/arm64 \
    -e WINEPREFIX="$prefix" \
    -e STRICT_FAIL_REGEX="$STRICT_FAIL_REGEX" \
    -v "$route_state:/state" \
    -v "$FEX_ROOTFS_BASE:/root/.fex-emu" \
    -v "$ROOT_DIR:/workspace" \
    -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
    "$image" \
    bash -s <<'INNER'
set -euo pipefail

FEX_ROOTFS=/root/.fex-emu/RootFS/Ubuntu_24_04
if [[ ! -d "$FEX_ROOTFS" ]]; then
  echo "FAIL: missing rootfs $FEX_ROOTFS" >&2
  exit 127
fi
if ! command -v FEXBash >/dev/null 2>&1; then
  echo "FAIL: FEXBash not found" >&2
  exit 127
fi

mkdir -p "$WINEPREFIX/drive_c" "$WINEPREFIX/dosdevices"
ln -sfn ../drive_c "$WINEPREFIX/dosdevices/c:"
ln -sfn "$FEX_ROOTFS" "$WINEPREFIX/dosdevices/z:"
ln -sfn /workspace "$WINEPREFIX/dosdevices/y:"

set +e
timeout 120 FEXBash -c "export WINEPREFIX='$WINEPREFIX'; /usr/lib/wine/wine64 wineboot.exe -u" > /tmp/cold_wineboot.log 2>&1
wb_rc=$?
set -e
if [[ "$wb_rc" -ne 0 ]]; then
  echo "FAIL: wineboot rc=$wb_rc" >&2
  sed -n '1,120p' /tmp/cold_wineboot.log
  exit 11
fi
if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_wineboot.log; then
  echo "FAIL: critical signature in wineboot log" >&2
  sed -n '1,120p' /tmp/cold_wineboot.log
  exit 12
fi

set +e
timeout 90 FEXBash -c "export WINEPREFIX='$WINEPREFIX'; /usr/lib/wine/wine64 y:/dolby_encoding_engine/dee.exe --help" > /tmp/cold_help.log 2>&1
help_rc=$?
set -e
if [[ "$help_rc" -ne 0 ]]; then
  echo "FAIL: help rc=$help_rc" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 13
fi
if ! grep -q "dee.exe, Version" /tmp/cold_help.log; then
  echo "FAIL: help signature missing" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 14
fi
if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_help.log; then
  echo "FAIL: critical signature in help log" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 15
fi

echo "PASS: fex-lab cold-start"
INNER
}

run_legacy_check() {
  local image="$1"
  local route_state="$STATE_DIR/legacy"
  local prefix="/state/WinePrefixes/cold_legacy"
  rm -rf "$route_state/${prefix#/state/}" || true
  mkdir -p "$route_state/${prefix#/state/}"

  docker run --rm --platform linux/amd64 \
    -e WINEPREFIX="$prefix" \
    -e STRICT_FAIL_REGEX="$STRICT_FAIL_REGEX" \
    -v "$route_state:/state" \
    -v "$ROOT_DIR:/workspace" \
    -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
    "$image" \
    bash -s <<'INNER'
set -euo pipefail

if [[ -x /usr/lib/wine/wine64 ]]; then
  wine_bin=/usr/lib/wine/wine64
elif command -v wine64 >/dev/null 2>&1; then
  wine_bin="$(command -v wine64)"
else
  echo "FAIL: wine64 binary not found" >&2
  exit 127
fi

mkdir -p "$WINEPREFIX/drive_c" "$WINEPREFIX/dosdevices"
ln -sfn ../drive_c "$WINEPREFIX/dosdevices/c:"
ln -sfn / "$WINEPREFIX/dosdevices/z:"
ln -sfn /workspace "$WINEPREFIX/dosdevices/y:"

set +e
timeout 120 "$wine_bin" wineboot.exe -u > /tmp/cold_wineboot.log 2>&1
wb_rc=$?
set -e
if [[ "$wb_rc" -ne 0 ]]; then
  echo "FAIL: wineboot rc=$wb_rc" >&2
  sed -n '1,120p' /tmp/cold_wineboot.log
  exit 11
fi
if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_wineboot.log; then
  echo "FAIL: critical signature in wineboot log" >&2
  sed -n '1,120p' /tmp/cold_wineboot.log
  exit 12
fi

set +e
timeout 90 "$wine_bin" y:/dolby_encoding_engine/dee.exe --help > /tmp/cold_help.log 2>&1
help_rc=$?
set -e
if [[ "$help_rc" -ne 0 ]]; then
  echo "FAIL: help rc=$help_rc" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 13
fi
if ! grep -q "dee.exe, Version" /tmp/cold_help.log; then
  echo "FAIL: help signature missing" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 14
fi
if [[ -n "$STRICT_FAIL_REGEX" ]] && grep -Eiq "$STRICT_FAIL_REGEX" /tmp/cold_help.log; then
  echo "FAIL: critical signature in help log" >&2
  sed -n '1,120p' /tmp/cold_help.log
  exit 15
fi

echo "PASS: legacy cold-start"
INNER
}

run_case() {
  local route="$1"
  local image="$2"
  local log
  local rc
  local critical
  local result
  local reason

  log="$(log_name_for "$route" "$image")"
  echo "[check] route=$route image=$image"

  if ! image_exists "$image"; then
    append_row "$route" "$image" "NA" "SKIP" "0" "image not present locally" "$log"
    return 0
  fi

  set +e
  case "$route" in
    bundled) run_bundled_check "$image" >"$log" 2>&1 ;;
    box64) run_box64_check "$image" >"$log" 2>&1 ;;
    fex-lab) run_fex_lab_check "$image" >"$log" 2>&1 ;;
    legacy) run_legacy_check "$image" >"$log" 2>&1 ;;
    *)
      echo "Unknown route: $route" >"$log"
      rc=99
      set -e
      append_row "$route" "$image" "99" "FAIL" "0" "unknown route" "$log"
      return 0
      ;;
  esac
  rc=$?
  set -e

  if [[ -n "$STRICT_FAIL_REGEX" ]]; then
    critical="$(grep -Eci "$STRICT_FAIL_REGEX" "$log" || true)"
  else
    critical="0"
  fi

  if [[ "$rc" -eq 0 ]]; then
    result="PASS"
    reason=""
  else
    result="FAIL"
    reason="$(grep -m1 '^FAIL:' "$log" || awk 'NF{line=$0} END{print line}' "$log")"
    reason="${reason//$'\r'/}"
    reason="${reason//$'\t'/ }"
  fi

  append_row "$route" "$image" "$rc" "$result" "$critical" "$reason" "$log"
}

for image in "${BUNDLED_IMAGES_DEFAULT[@]}"; do
  run_case "bundled" "$image"
done

for image in "${BOX64_IMAGES_DEFAULT[@]}"; do
  run_case "box64" "$image"
done

for image in "${FEX_LAB_IMAGES_DEFAULT[@]}"; do
  run_case "fex-lab" "$image"
done

if [[ "$INCLUDE_LEGACY" == "1" ]]; then
  for image in "${LEGACY_IMAGES_DEFAULT[@]}"; do
    run_case "legacy" "$image"
  done
fi

echo
echo "Summary TSV: $SUMMARY_TSV"
if command -v column >/dev/null 2>&1; then
  column -t -s $'\t' "$SUMMARY_TSV"
else
  cat "$SUMMARY_TSV"
fi
