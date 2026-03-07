#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-dee-box64-lab:local}"
DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_box64_state}"
WINEPREFIX="${WINEPREFIX:-/state/WinePrefixes/dee}"
WINEARCH="${WINEARCH:-win64}"
WINEBOOT_TIMEOUT="${WINEBOOT_TIMEOUT:-120}"
BOX64_BIN="${BOX64_BIN:-/usr/bin/box64}"
WINE_BIN="${WINE_BIN:-/usr/bin/wine64}"
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

mkdir -p "$STATE_DIR"

if [[ $# -eq 0 ]]; then
  set -- --help
fi

ARGS=("$@")
prepare_workspace_dirs_from_args "${ARGS[@]}"
ARGS_Q="$(printf '%q ' "${ARGS[@]}")"

echo "Running DEE under Box64 container image: $IMAGE_TAG"
docker run --rm --platform linux/arm64 \
  -v "$STATE_DIR:/state" \
  -v "$ROOT_DIR:/workspace" \
  -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
  "$IMAGE_TAG" bash -lc "
    set -euo pipefail
    export WINEPREFIX='$WINEPREFIX'
    export WINEARCH='$WINEARCH'
    export BOX64_NOBANNER=1
    export WINEDEBUG=fixme-all

    test -x '$BOX64_BIN'
    if [[ -x '$WINE_BIN' ]]; then
      wine_bin='$WINE_BIN'
    elif [[ -x /usr/bin/wine64 ]]; then
      wine_bin=/usr/bin/wine64
    elif [[ -x /usr/lib/wine/wine64 ]]; then
      wine_bin=/usr/lib/wine/wine64
    else
      echo 'wine64 binary not found in container' >&2
      exit 127
    fi

    mkdir -p \"\$WINEPREFIX/drive_c\" \"\$WINEPREFIX/dosdevices\"
    ln -sfn ../drive_c \"\$WINEPREFIX/dosdevices/c:\"
    ln -sfn / \"\$WINEPREFIX/dosdevices/z:\"
    ln -sfn /workspace \"\$WINEPREFIX/dosdevices/y:\"

    if [[ ! -f \"\$WINEPREFIX/.dee_box64_ready\" ]]; then
      timeout '$WINEBOOT_TIMEOUT' '$BOX64_BIN' \"\$wine_bin\" wineboot.exe -u >/dev/null 2>&1 || true
      touch \"\$WINEPREFIX/.dee_box64_ready\"
    fi

    '$BOX64_BIN' \"\$wine_bin\" '$DEE_WIN_EXE' $ARGS_Q
  "
