#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-dee-box64-lab:local}"
PLATFORM="${PLATFORM:-linux/arm64}"
MODE="${MODE:-encode}" # help | encode
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_box64_state_allowlist}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/tmp_box64_prune/allowlist}"
WINEPREFIX="${WINEPREFIX:-/state/WinePrefixes/dee_allowlist}"
WINEARCH="${WINEARCH:-win64}"
WINEBOOT_TIMEOUT="${WINEBOOT_TIMEOUT:-120}"

DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
DEE_WIN_EXE="${DEE_WIN_EXE:-y:/dolby_encoding_engine/dee.exe}"
XML_PATH="y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml"
INPUT_PATH="y:/testADM.wav"
LICENSE_PATH="y:/dolby_encoding_engine/license.lic"

usage() {
  cat <<'EOF'
Usage:
  scripts/generate_box64_runtime_allowlist.sh [options]

Options:
  --image TAG       source image tag (default: dee-box64-lab:local)
  --mode MODE       command mode: help|encode (default: encode)
  --state-dir DIR   host state directory
  --out-dir DIR     output directory for traces and allowlist
  --platform PLAT   docker platform (default: linux/arm64)
  -h, --help        show help
EOF
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

to_abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$ROOT_DIR/$p"
  fi
}

STATE_DIR="$(to_abs_path "$STATE_DIR")"
OUT_DIR="$(to_abs_path "$OUT_DIR")"

case "$MODE" in
  help|encode) ;;
  *)
    echo "Invalid --mode: $MODE (expected help|encode)" >&2
    exit 2
    ;;
esac

if [[ ! -d "$DEE_DIR" ]]; then
  echo "DEE directory not found: $DEE_DIR" >&2
  exit 1
fi

if [[ ! -f "$DEE_DIR/dee.exe" ]]; then
  echo "dee.exe not found: $DEE_DIR/dee.exe" >&2
  exit 1
fi

if [[ "$MODE" == "encode" ]]; then
  [[ -f "$ROOT_DIR/testADM.wav" ]] || { echo "Input audio not found: $ROOT_DIR/testADM.wav" >&2; exit 1; }
  [[ -f "$DEE_DIR/license.lic" ]] || { echo "License not found: $DEE_DIR/license.lic" >&2; exit 1; }
fi

mkdir -p "$STATE_DIR" "$OUT_DIR"
rm -f "$OUT_DIR"/trace*

if [[ "$MODE" == "help" ]]; then
  ARGS=(--help)
else
  ENCODE_HOST_DIR="$ROOT_DIR/tmp_box64_acceptance/allowlist_trace"
  mkdir -p "$ENCODE_HOST_DIR/tmp"
  ARGS=(
    --xml "$XML_PATH"
    --input-audio "$INPUT_PATH"
    --output "y:/tmp_box64_acceptance/allowlist_trace/probe.ec3"
    --temp "y:/tmp_box64_acceptance/allowlist_trace/tmp"
    --log-file "y:/tmp_box64_acceptance/allowlist_trace/probe.log"
    -l "$LICENSE_PATH"
    --stdout
    --verbose info
  )
fi
ARGS_Q="$(printf '%q ' "${ARGS[@]}")"

echo "Running trace in image: $IMAGE_TAG (mode=$MODE)"
docker run --rm --platform "$PLATFORM" \
  -v "$STATE_DIR:/state" \
  -v "$ROOT_DIR:/workspace" \
  -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
  -v "$OUT_DIR:/trace_out" \
  "$IMAGE_TAG" bash -lc "
    set -euo pipefail
    export WINEPREFIX='$WINEPREFIX'
    export WINEARCH='$WINEARCH'
    export BOX64_NOBANNER=1
    export WINEDEBUG=fixme-all

    box64_bin=\"\$(command -v box64 || true)\"
    if [[ -z \"\$box64_bin\" ]]; then
      echo 'box64 not found' >&2
      exit 127
    fi

    if [[ -x /usr/lib/wine/wine64 ]]; then
      wine_bin=/usr/lib/wine/wine64
    elif [[ -x /usr/bin/wine64 ]]; then
      wine_bin=/usr/bin/wine64
    else
      echo 'wine64 binary not found' >&2
      exit 127
    fi

    if ! command -v strace >/dev/null 2>&1; then
      apt-get update >/dev/null
      apt-get install -y --no-install-recommends strace >/dev/null
      rm -rf /var/lib/apt/lists/*
    fi

    mkdir -p \"\$WINEPREFIX/drive_c\" \"\$WINEPREFIX/dosdevices\"
    ln -sfn ../drive_c \"\$WINEPREFIX/dosdevices/c:\"
    ln -sfn / \"\$WINEPREFIX/dosdevices/z:\"
    ln -sfn /workspace \"\$WINEPREFIX/dosdevices/y:\"

    if [[ ! -f \"\$WINEPREFIX/.dee_box64_ready\" ]]; then
      timeout '$WINEBOOT_TIMEOUT' \"\$box64_bin\" \"\$wine_bin\" wineboot.exe -u >/dev/null 2>&1 || true
      touch \"\$WINEPREFIX/.dee_box64_ready\"
    fi

    strace -ff -s 0 -e trace=file -o /trace_out/trace \
      \"\$box64_bin\" \"\$wine_bin\" '$DEE_WIN_EXE' $ARGS_Q
  "

RAW_TRACE="$OUT_DIR/runtime-allowlist.raw.txt"
FILTERED="$OUT_DIR/runtime-allowlist.filtered.txt"
ALLOWLIST="$OUT_DIR/runtime-allowlist.txt"
SUMMARY="$OUT_DIR/runtime-allowlist.md"

if ! ls "$OUT_DIR"/trace* >/dev/null 2>&1; then
  echo "Trace output missing in: $OUT_DIR" >&2
  exit 1
fi

grep -hoE '"(/[^"]+)"' "$OUT_DIR"/trace* | tr -d '"' | sort -u > "$RAW_TRACE"

awk '
  /^\/usr\// { print; next }
  /^\/lib\// { print; next }
  /^\/lib64\// { print; next }
  /^\/etc\/ld.so/ { print; next }
  /^\/bin\/bash$/ { print; next }
  /^\/usr\/bin\/timeout$/ { print; next }
' "$RAW_TRACE" | sort -u > "$FILTERED"

  {
    cat "$FILTERED"
    echo "/usr/local/bin/box64"
    echo "/usr/lib/wine/wine64"
    echo "/usr/lib/wine/wineserver"
    echo "/usr/lib/wine/wineserver64"
    echo "/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/services.exe"
    echo "/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/wineboot.exe"
    echo "/bin/bash"
    echo "/usr/bin/timeout"
  } | sort -u > "$OUT_DIR/runtime-allowlist.candidates.txt"

docker run --rm --platform "$PLATFORM" \
  -v "$OUT_DIR/runtime-allowlist.candidates.txt:/tmp/candidates.txt:ro" \
  "$IMAGE_TAG" bash -lc '
    set -euo pipefail
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if [[ -f "$p" || -L "$p" ]]; then
        echo "$p"
      fi
    done < /tmp/candidates.txt
  ' | sort -u > "$ALLOWLIST"

{
  echo "# Box64 Runtime Allowlist"
  echo ""
  echo "- Image: \`$IMAGE_TAG\`"
  echo "- Mode: \`$MODE\`"
  echo "- Generated: \`$(date '+%Y-%m-%d %H:%M:%S %z')\`"
  echo "- Candidate paths: \`$(wc -l < "$OUT_DIR/runtime-allowlist.candidates.txt" | tr -d ' ')\`"
  echo "- File/symlink allowlist paths: \`$(wc -l < "$ALLOWLIST" | tr -d ' ')\`"
  echo ""
  echo "Artifacts:"
  echo "- \`$ALLOWLIST\`"
  echo "- \`$RAW_TRACE\`"
  echo "- \`$FILTERED\`"
} > "$SUMMARY"

echo "Allowlist generated: $ALLOWLIST"
