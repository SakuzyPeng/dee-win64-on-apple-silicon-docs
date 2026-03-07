#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-dee-fex-lab:local}"
ROOTFS_BASE="${ROOTFS_BASE:-$ROOT_DIR/tmp_fex_rootfs}"
FEX_ROOTFS="${FEX_ROOTFS:-$ROOTFS_BASE/RootFS/Ubuntu_24_04}"
DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
WINEPREFIX="${WINEPREFIX:-/root/.fex-emu/WinePrefixes/dee}"
WINEBOOT_TIMEOUT="${WINEBOOT_TIMEOUT:-120}"
WINE_BIN="${WINE_BIN:-/usr/lib/wine/wine64}"
DEE_WIN_EXE="${DEE_WIN_EXE:-y:/dolby_encoding_engine/dee.exe}"

win_to_workspace_path() {
  local win_path="$1"
  local rel
  if [[ "$win_path" =~ ^[Yy]:[\\/](.*)$ ]]; then
    rel="${BASH_REMATCH[1]}"
    rel="${rel//\\//}"
    echo "$ROOT_DIR/$rel"
    return 0
  fi
  return 1
}

prepare_workspace_dirs_from_args() {
  local args=("$@")
  local idx=0 opt val host_path
  while (( idx < ${#args[@]} )); do
    opt="${args[$idx]}"
    case "$opt" in
      --temp|--log-file|--output)
        if (( idx + 1 < ${#args[@]} )); then
          val="${args[$((idx + 1))]}"
          if host_path="$(win_to_workspace_path "$val")"; then
            case "$opt" in
              --temp)
                mkdir -p "$host_path"
                ;;
              --log-file|--output)
                mkdir -p "$(dirname "$host_path")"
                ;;
            esac
          fi
          idx=$((idx + 2))
          continue
        fi
        ;;
    esac
    idx=$((idx + 1))
  done
}

if [[ ! -d "$DEE_DIR" ]]; then
  echo "DEE directory not found: $DEE_DIR" >&2
  exit 1
fi

if [[ ! -f "$DEE_DIR/dee.exe" ]]; then
  echo "dee.exe not found: $DEE_DIR/dee.exe" >&2
  exit 1
fi

if [[ ! -d "$FEX_ROOTFS" ]]; then
  echo "FEX_ROOTFS directory not found: $FEX_ROOTFS" >&2
  echo "Run scripts/prepare_fex_rootfs.sh first." >&2
  exit 1
fi

check_wine_bin_path=""
case "$WINE_BIN" in
  /usr/lib/wine/wine|wine)
    if [[ -x "$FEX_ROOTFS/usr/lib/wine/wine" ]]; then
      check_wine_bin_path="/usr/lib/wine/wine"
    elif [[ -x "$FEX_ROOTFS/usr/lib/wine/wine64" ]]; then
      check_wine_bin_path="/usr/lib/wine/wine64"
    fi
    ;;
  /usr/lib/wine/wine64|wine64)
    check_wine_bin_path="/usr/lib/wine/wine64"
    ;;
  /*)
    check_wine_bin_path="$WINE_BIN"
    ;;
esac

if [[ -n "$check_wine_bin_path" && ! -x "$FEX_ROOTFS$check_wine_bin_path" ]]; then
  echo "Wine binary not found in rootfs: $FEX_ROOTFS$check_wine_bin_path" >&2
  echo "Run scripts/install_wine_in_fex_rootfs_chroot.sh first." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  set -- --help
fi

ARGS=("$@")
prepare_workspace_dirs_from_args "${ARGS[@]}"
ARGS_Q="$(printf '%q ' "${ARGS[@]}")"
ROOTFS_NAME="$(basename "$FEX_ROOTFS")"

echo "Running DEE under FEX rootfs: $FEX_ROOTFS"
docker run --rm --platform linux/arm64 \
  -v "$ROOTFS_BASE:/root/.fex-emu" \
  -v "$ROOT_DIR:/workspace" \
  -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
  "$IMAGE_TAG" bash -lc "
    set -euo pipefail
    export FEX_ROOTFS=/root/.fex-emu/RootFS/$ROOTFS_NAME
    export WINEPREFIX='$WINEPREFIX'

    mkdir -p \"\$WINEPREFIX/drive_c\" \"\$WINEPREFIX/dosdevices\"
    ln -sfn ../drive_c \"\$WINEPREFIX/dosdevices/c:\"
    ln -sfn \"\$FEX_ROOTFS\" \"\$WINEPREFIX/dosdevices/z:\"
    ln -sfn /workspace \"\$WINEPREFIX/dosdevices/y:\"

    if [[ ! -f \"\$WINEPREFIX/.dee_fex_ready\" ]]; then
      timeout '$WINEBOOT_TIMEOUT' FEXBash -c \"export WINEPREFIX='\$WINEPREFIX'; /usr/lib/wine/wine64 wineboot.exe -u\" >/dev/null 2>&1 || true
      touch \"\$WINEPREFIX/.dee_fex_ready\"
    fi

    FEXBash -c \"export WINEPREFIX='\$WINEPREFIX'; $WINE_BIN '$DEE_WIN_EXE' $ARGS_Q\"
  "
