#!/usr/bin/env bash
# capture_fex_bundled_allowlist.sh
# Offline trace collector for FEX bundled image runtime allowlists.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-dee-fex-bundled:phase1-safe}"
PLATFORM="${PLATFORM:-linux/arm64}"
MODE="${MODE:-both}" # help | encode | both
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_fex_bundled_allowlist/state}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/tmp_fex_bundled_allowlist/out}"
ALLOWLIST_OUT="${ALLOWLIST_OUT:-$ROOT_DIR/configs/fex_bundled_allowlist.txt}"
AGGRESSIVE_OUT="${AGGRESSIVE_OUT:-$ROOT_DIR/configs/fex_bundled_aggressive_allowlist.txt}"
WINEPREFIX="${WINEPREFIX:-/state/WinePrefixes/dee_allowlist}"
WINEBOOT_TIMEOUT="${WINEBOOT_TIMEOUT:-120}"

DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
DEE_WIN_EXE="${DEE_WIN_EXE:-y:/dolby_encoding_engine/dee.exe}"
WINE_BIN="${WINE_BIN:-/usr/lib/wine/wine64}"
ROOTFS_PATH_IN_IMAGE="/root/.fex-emu/RootFS/Ubuntu_24_04"

usage() {
  cat <<'EOF'
Usage:
  scripts/capture_fex_bundled_allowlist.sh [options]

Options:
  --image TAG             bundled image tag (default: dee-fex-bundled:phase1-safe)
  --mode MODE             help|encode|both (default: both)
  --state-dir DIR         state directory
  --out-dir DIR           trace output directory
  --allowlist-out FILE    output builtin allowlist file
  --aggressive-out FILE   output aggressive (.so) allowlist file
  --platform PLAT         docker platform (default: linux/arm64)
  -h, --help              show help
EOF
}

to_abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$ROOT_DIR/$p"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      shift
      IMAGE_TAG="${1:-}"
      ;;
    --mode)
      shift
      MODE="${1:-}"
      ;;
    --state-dir)
      shift
      STATE_DIR="${1:-}"
      ;;
    --out-dir)
      shift
      OUT_DIR="${1:-}"
      ;;
    --allowlist-out)
      shift
      ALLOWLIST_OUT="${1:-}"
      ;;
    --aggressive-out)
      shift
      AGGRESSIVE_OUT="${1:-}"
      ;;
    --platform)
      shift
      PLATFORM="${1:-}"
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

STATE_DIR="$(to_abs_path "$STATE_DIR")"
OUT_DIR="$(to_abs_path "$OUT_DIR")"
ALLOWLIST_OUT="$(to_abs_path "$ALLOWLIST_OUT")"
AGGRESSIVE_OUT="$(to_abs_path "$AGGRESSIVE_OUT")"

case "$MODE" in
  help|encode|both) ;;
  *)
    echo "Invalid --mode: $MODE (expected help|encode|both)" >&2
    exit 2
    ;;
esac

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "Image not found: $IMAGE_TAG" >&2
  exit 1
fi

if [[ ! -d "$DEE_DIR" ]]; then
  echo "DEE directory not found: $DEE_DIR" >&2
  exit 1
fi

if [[ ! -f "$DEE_DIR/dee.exe" ]]; then
  echo "dee.exe not found: $DEE_DIR/dee.exe" >&2
  exit 1
fi

if [[ "$MODE" != "help" ]] && [[ ! -f "$ROOT_DIR/testADM.wav" ]]; then
  echo "Input audio not found: $ROOT_DIR/testADM.wav" >&2
  exit 1
fi

mkdir -p "$STATE_DIR" "$OUT_DIR" "$(dirname "$ALLOWLIST_OUT")" "$(dirname "$AGGRESSIVE_OUT")"
rm -f "$OUT_DIR"/help_cold.trace* "$OUT_DIR"/encode.trace* "$OUT_DIR"/*.log

run_trace_case() {
  local case_name="$1"
  local dee_args_q="$2"
  local reset_prefix="$3"

  local stdout_log="$OUT_DIR/${case_name}.stdout.log"
  local stderr_log="$OUT_DIR/${case_name}.stderr.log"

  echo "Tracing case: $case_name"
  docker run --rm --platform "$PLATFORM" \
    -v "$STATE_DIR:/state" \
    -v "$OUT_DIR:/trace_out" \
    -v "$ROOT_DIR:/workspace" \
    -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
    "$IMAGE_TAG" bash -lc "
      set -euo pipefail
      export WINEPREFIX='$WINEPREFIX'
      export WINEDEBUG=fixme-all

      if ! command -v strace >/dev/null 2>&1; then
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends strace >/dev/null
        rm -rf /var/lib/apt/lists/*
      fi

      if [[ '$reset_prefix' = '1' ]]; then
        rm -rf \"\$WINEPREFIX\"
      fi

      mkdir -p \"\$WINEPREFIX/drive_c\" \"\$WINEPREFIX/dosdevices\"
      ln -sfn ../drive_c             \"\$WINEPREFIX/dosdevices/c:\"
      ln -sfn '$ROOTFS_PATH_IN_IMAGE' \"\$WINEPREFIX/dosdevices/z:\"
      ln -sfn /workspace              \"\$WINEPREFIX/dosdevices/y:\"
      mkdir -p /workspace/tmp_fex_bundled_allowlist/out/tmp

      if [[ ! -f \"\$WINEPREFIX/.dee_fex_bundled_ready\" ]]; then
        strace -ff -s 0 -e trace=file -o /trace_out/$case_name.wineboot.trace \
          timeout '$WINEBOOT_TIMEOUT' \
            FEX /bin/bash -c \"WINEPREFIX=\$WINEPREFIX WINEDEBUG=fixme-all $WINE_BIN wineboot.exe -u\" >/dev/null 2>&1
        touch \"\$WINEPREFIX/.dee_fex_bundled_ready\"
      fi

      dee_cmd=\"WINEPREFIX=\$WINEPREFIX WINEDEBUG=fixme-all $WINE_BIN $DEE_WIN_EXE $dee_args_q\"
      strace -ff -s 0 -e trace=file -o /trace_out/$case_name.trace \
        FEX /bin/bash -c \"\$dee_cmd\"
    " >"$stdout_log" 2>"$stderr_log"
}

help_args=(--help)
help_args_q="$(printf '%q ' "${help_args[@]}")"

encode_args=(
  --xml "y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml"
  --input-audio "y:/testADM.wav"
  --output "y:/tmp_fex_bundled_allowlist/out/probe.ec3"
  --temp "y:/tmp_fex_bundled_allowlist/out/tmp"
  --log-file "y:/tmp_fex_bundled_allowlist/out/probe.log"
  --stdout
  --verbose info
)
encode_args_q="$(printf '%q ' "${encode_args[@]}")"

if [[ "$MODE" == "help" || "$MODE" == "both" ]]; then
  run_trace_case "help_cold" "$help_args_q" "1"
fi

if [[ "$MODE" == "encode" || "$MODE" == "both" ]]; then
  run_trace_case "encode" "$encode_args_q" "0"
fi

if ! ls "$OUT_DIR"/*.trace* >/dev/null 2>&1; then
  echo "No trace files found in: $OUT_DIR" >&2
  exit 1
fi

RAW_PATHS="$OUT_DIR/fex_bundled_allowlist.raw_paths.txt"
AUTO_BUILTINS="$OUT_DIR/fex_bundled_allowlist.auto_builtins.txt"
AUTO_SO="$OUT_DIR/fex_bundled_allowlist.auto_so.txt"
SUMMARY_MD="$OUT_DIR/fex_bundled_allowlist.summary.md"

grep -hoE '"(/[^"]+)"' "$OUT_DIR"/*.trace* | tr -d '"' | sort -u > "$RAW_PATHS"

awk -v rootfs="$ROOTFS_PATH_IN_IMAGE" '
  {
    p = $0
    if (index(p, rootfs) == 1) sub("^" rootfs, "", p)
    if (index(p, "/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/") == 1) print p
  }
' "$RAW_PATHS" | sort -u > "$AUTO_BUILTINS"

awk -v rootfs="$ROOTFS_PATH_IN_IMAGE" '
  {
    p = $0
    if (index(p, rootfs) == 1) sub("^" rootfs, "", p)
    if (index(p, "/usr/lib/x86_64-linux-gnu/") == 1 && p !~ /\/wine\//) {
      if (p ~ /\/ld-linux-x86-64\.so\.2$/ || p ~ /\.so(\..*)?$/) print p
    }
  }
' "$RAW_PATHS" | sort -u > "$AUTO_SO"

TMP_BUILTINS="$(mktemp)"
TMP_SO="$(mktemp)"
trap 'rm -f "$TMP_BUILTINS" "$TMP_SO"' EXIT

{
  [[ -f "$ALLOWLIST_OUT" ]] && awk 'NF && $1 !~ /^#/' "$ALLOWLIST_OUT"
  cat "$AUTO_BUILTINS"
  cat <<'KEEP_BUILTINS'
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/ntdll.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/kernelbase.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/kernel32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/user32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/ole32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/oleaut32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/ucrtbase.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/msvcrt.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/rpcrt4.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/advapi32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/sechost.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/ws2_32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/shcore.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/shlwapi.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/shell32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/combase.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/comctl32.dll
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/ntoskrnl.exe
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/mountmgr.sys
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/wineboot.exe
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/winedevice.exe
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/services.exe
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/rundll32.exe
/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/explorer.exe
KEEP_BUILTINS
} | sort -u > "$TMP_BUILTINS"

{
  [[ -f "$AGGRESSIVE_OUT" ]] && awk 'NF && $1 !~ /^#/' "$AGGRESSIVE_OUT"
  cat "$AUTO_SO"
  cat <<'KEEP_SO'
/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
/usr/lib/x86_64-linux-gnu/libc.so.6
/usr/lib/x86_64-linux-gnu/libm.so.6
/usr/lib/x86_64-linux-gnu/libdl.so.2
/usr/lib/x86_64-linux-gnu/libpthread.so.0
/usr/lib/x86_64-linux-gnu/librt.so.1
/usr/lib/x86_64-linux-gnu/libgcc_s.so.1
/usr/lib/x86_64-linux-gnu/libstdc++.so.6
/usr/lib/x86_64-linux-gnu/libz.so.1
/usr/lib/x86_64-linux-gnu/libtinfo.so.6
/usr/lib/x86_64-linux-gnu/libwine.so.1
KEEP_SO
} | sort -u > "$TMP_SO"

{
  echo "# FEX bundled allowlist (wine builtins)"
  echo "# Generated by scripts/capture_fex_bundled_allowlist.sh"
  echo "# Generated at: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "# Source image: $IMAGE_TAG"
  echo ""
  cat "$TMP_BUILTINS"
} > "$ALLOWLIST_OUT"

{
  echo "# FEX bundled aggressive allowlist (x86_64 non-wine .so)"
  echo "# Generated by scripts/capture_fex_bundled_allowlist.sh"
  echo "# Generated at: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "# Source image: $IMAGE_TAG"
  echo ""
  cat "$TMP_SO"
} > "$AGGRESSIVE_OUT"

{
  echo "# FEX Bundled Allowlist Capture"
  echo ""
  echo "- Image: \`$IMAGE_TAG\`"
  echo "- Mode: \`$MODE\`"
  echo "- Generated: \`$(date '+%Y-%m-%d %H:%M:%S %z')\`"
  echo "- Raw traced paths: \`$(wc -l < "$RAW_PATHS" | tr -d ' ')\`"
  echo "- Builtin allowlist entries: \`$(awk 'NF && $1 !~ /^#/' "$ALLOWLIST_OUT" | wc -l | tr -d ' ')\`"
  echo "- Aggressive allowlist entries: \`$(awk 'NF && $1 !~ /^#/' "$AGGRESSIVE_OUT" | wc -l | tr -d ' ')\`"
  echo ""
  echo "Artifacts:"
  echo "- \`$RAW_PATHS\`"
  echo "- \`$AUTO_BUILTINS\`"
  echo "- \`$AUTO_SO\`"
  echo "- \`$ALLOWLIST_OUT\`"
  echo "- \`$AGGRESSIVE_OUT\`"
} > "$SUMMARY_MD"

echo "Allowlist capture done."
echo "Builtin allowlist: $ALLOWLIST_OUT"
echo "Aggressive allowlist: $AGGRESSIVE_OUT"
echo "Summary: $SUMMARY_MD"
