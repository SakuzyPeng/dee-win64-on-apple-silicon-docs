#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DME_MODE="${DME_MODE:-box64}"
DME_DIR="${DME_DIR:-$ROOT_DIR/dme_encoder}"
TOOL_NAME=""
MP4MUXER_NATIVE_BIN="${MP4MUXER_NATIVE_BIN:-}"
AUTO_NATIVE_MP4MUXER="${AUTO_NATIVE_MP4MUXER:-1}"

IMAGE_TAG_BOX64="${IMAGE_TAG_BOX64:-dee-box64-lab:local}"
IMAGE_TAG_FEX="${IMAGE_TAG_FEX:-dee-fex-lab:local}"

HOST_WINE_BIN="${HOST_WINE_BIN:-wine64}"
HOST_WINEPREFIX="${HOST_WINEPREFIX:-$ROOT_DIR/tmp_host_wineprefix_dme}"
HOST_WINEARCH="${HOST_WINEARCH:-win64}"
HOST_WINEDEBUG="${HOST_WINEDEBUG:-fixme-all}"

usage() {
  cat <<USAGE
Usage:
  scripts/run_dme_cli.sh --tool <exe_name> [tool_args...]

Modes:
  DME_MODE=box64|fex|host   (default: box64)

Examples:
  DME_MODE=box64 scripts/run_dme_cli.sh --tool dee_ddpjoc_encoder.exe --help
  DME_MODE=fex scripts/run_dme_cli.sh --tool mp4muxer.exe --help
  DME_MODE=host scripts/run_dme_cli.sh --tool dee_ddp_encoder.exe --help

Native mp4muxer override:
  MP4MUXER_NATIVE_BIN=/path/to/native/mp4muxer \
  DME_MODE=box64 scripts/run_dme_cli.sh --tool mp4muxer.exe --input-file y:/in.ec3 ...
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

if [[ "$1" != "--tool" ]]; then
  usage
  exit 1
fi
TOOL_NAME="$2"
shift 2

if [[ -z "$TOOL_NAME" ]]; then
  echo "--tool requires a value" >&2
  exit 1
fi

if [[ ! -f "$DME_DIR/$TOOL_NAME" ]]; then
  echo "Tool not found: $DME_DIR/$TOOL_NAME" >&2
  exit 1
fi

convert_win_path_to_host() {
  local p="$1"
  if [[ "$p" =~ ^[Yy]:[\\/](.*)$ ]]; then
    local rel="${BASH_REMATCH[1]}"
    rel="${rel//\\//}"
    printf '%s\n' "$ROOT_DIR/$rel"
    return 0
  fi

  if [[ "$p" =~ ^[Zz]:[\\/]workspace[\\/](.*)$ ]]; then
    local rel="${BASH_REMATCH[1]}"
    rel="${rel//\\//}"
    printf '%s\n' "$ROOT_DIR/$rel"
    return 0
  fi

  printf '%s\n' "$p"
}

prepare_dirs_from_args() {
  local args=("$@")
  local idx=0 opt val host_path
  while (( idx < ${#args[@]} )); do
    opt="${args[$idx]}"
    case "$opt" in
      --temp|--temp-dir|--output|--output-file|--log-file)
        if (( idx + 1 < ${#args[@]} )); then
          val="${args[$((idx + 1))]}"
          host_path="$(convert_win_path_to_host "$val")"
          case "$opt" in
            --temp|--temp-dir)
              mkdir -p "$host_path"
              ;;
            --output|--output-file|--log-file)
              mkdir -p "$(dirname "$host_path")"
              ;;
          esac
          idx=$((idx + 2))
          continue
        fi
        ;;
    esac
    idx=$((idx + 1))
  done
}

run_native_mp4muxer_if_configured() {
  local args=("$@")
  local converted=()
  local translated=()
  local idx=0
  local auto_candidate=""

  if [[ "$TOOL_NAME" != "mp4muxer.exe" ]]; then
    return 1
  fi

  if [[ -z "$MP4MUXER_NATIVE_BIN" && "$AUTO_NATIVE_MP4MUXER" != "0" ]]; then
    auto_candidate="$ROOT_DIR/../upstream/dlb_mp4base/make/mp4muxer/macos/mp4muxer_release"
    if [[ -x "$auto_candidate" ]]; then
      MP4MUXER_NATIVE_BIN="$auto_candidate"
    fi
  fi

  if [[ -z "$MP4MUXER_NATIVE_BIN" ]]; then
    return 1
  fi

  if [[ ! -x "$MP4MUXER_NATIVE_BIN" ]]; then
    echo "MP4MUXER_NATIVE_BIN is not executable: $MP4MUXER_NATIVE_BIN" >&2
    exit 1
  fi

  while (( idx < ${#args[@]} )); do
    converted+=("$(convert_win_path_to_host "${args[$idx]}")")
    idx=$((idx + 1))
  done

  idx=0
  while (( idx < ${#converted[@]} )); do
    case "${converted[$idx]}" in
      --input-format)
        # Native dlb_mp4base mp4muxer infers stream type from extension
        # and does not accept Windows-style --input-format.
        idx=$((idx + 2))
        continue
        ;;
      *)
        translated+=("${converted[$idx]}")
        ;;
    esac
    idx=$((idx + 1))
  done

  prepare_dirs_from_args "${translated[@]}"
  exec "$MP4MUXER_NATIVE_BIN" "${translated[@]}"
}

run_native_mp4muxer_if_configured "$@" || true

case "$DME_MODE" in
  box64)
    prepare_dirs_from_args "$@"
    exec env IMAGE_TAG="$IMAGE_TAG_BOX64" DEE_WIN_EXE="y:/dme_encoder/$TOOL_NAME" \
      "$ROOT_DIR/scripts/run_dee_with_box64.sh" "$@"
    ;;
  fex)
    prepare_dirs_from_args "$@"
    exec env IMAGE_TAG="$IMAGE_TAG_FEX" DEE_WIN_EXE="y:/dme_encoder/$TOOL_NAME" \
      "$ROOT_DIR/scripts/run_dee_with_fex.sh" "$@"
    ;;
  host)
    if ! command -v "$HOST_WINE_BIN" >/dev/null 2>&1; then
      echo "Host wine binary not found: $HOST_WINE_BIN" >&2
      exit 127
    fi

    mkdir -p "$HOST_WINEPREFIX"
    export WINEPREFIX="$HOST_WINEPREFIX"
    export WINEARCH="$HOST_WINEARCH"
    export WINEDEBUG="$HOST_WINEDEBUG"

    if [[ ! -f "$HOST_WINEPREFIX/.dme_host_ready" ]]; then
      "$HOST_WINE_BIN" wineboot -u >/dev/null 2>&1 || true
      touch "$HOST_WINEPREFIX/.dme_host_ready"
    fi

    prepare_dirs_from_args "$@"
    exec "$HOST_WINE_BIN" "z:$DME_DIR/$TOOL_NAME" "$@"
    ;;
  *)
    echo "Unsupported DME_MODE: $DME_MODE" >&2
    echo "Use one of: box64, fex, host" >&2
    exit 2
    ;;
esac
