#!/usr/bin/env bash
# run_dee_with_fex_bundled.sh
#
# 使用内嵌 RootFS 的 FEX bundled 镜像运行 DEE。
# 与 run_dee_with_fex.sh 的核心区别：
#   - RootFS 已打包在镜像内，无需挂载外部 tmp_fex_rootfs/
#   - WinePrefix 独立持久化到 STATE_DIR
#   - 使用 FEX 直接运行 wine64，无需 rootfs 内有 x86-64 bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-dee-fex-bundled:phase2-balanced-v5}"
DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_fex_bundled_state}"
WINEPREFIX="${WINEPREFIX:-/state/WinePrefixes/dee}"
WINEBOOT_TIMEOUT="${WINEBOOT_TIMEOUT:-120}"
AUTO_RESET_PREFIX_ON_IMAGE_CHANGE="${AUTO_RESET_PREFIX_ON_IMAGE_CHANGE:-1}"
RESET_WINEPREFIX="${RESET_WINEPREFIX:-0}"
FEX_ROOTFS_IN_IMAGE="/root/.fex-emu/RootFS/Ubuntu_24_04"
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

resolve_image_identity() {
  local repo_digest image_id
  repo_digest="$(docker image inspect "$IMAGE_TAG" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
  if [[ -n "$repo_digest" && "$repo_digest" != "<no value>" ]]; then
    printf '%s\n' "$repo_digest"
    return 0
  fi

  image_id="$(docker image inspect "$IMAGE_TAG" --format '{{.Id}}' 2>/dev/null || true)"
  if [[ -n "$image_id" && "$image_id" != "<no value>" ]]; then
    printf '%s\n' "$image_id"
    return 0
  fi

  return 1
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

HOST_PREFIX_PATH=""
if [[ "$WINEPREFIX" == /state/* ]]; then
  HOST_PREFIX_PATH="$STATE_DIR/${WINEPREFIX#/state/}"
fi

STATE_META_DIR="$STATE_DIR/.dee_fex_bundled_meta"
STATE_IMAGE_MARKER="$STATE_META_DIR/image_ref.txt"
CURRENT_IMAGE_IDENTITY=""
if CURRENT_IMAGE_IDENTITY="$(resolve_image_identity)"; then
  mkdir -p "$STATE_META_DIR"
fi

if [[ "$RESET_WINEPREFIX" == "1" ]]; then
  if [[ -n "$HOST_PREFIX_PATH" ]]; then
    echo "Resetting bundled WinePrefix due to RESET_WINEPREFIX=1: $HOST_PREFIX_PATH" >&2
    rm -rf "$HOST_PREFIX_PATH"
  fi
elif [[ "$AUTO_RESET_PREFIX_ON_IMAGE_CHANGE" == "1" && -n "$HOST_PREFIX_PATH" && -n "$CURRENT_IMAGE_IDENTITY" ]]; then
  PREV_IMAGE_IDENTITY=""
  if [[ -f "$STATE_IMAGE_MARKER" ]]; then
    PREV_IMAGE_IDENTITY="$(cat "$STATE_IMAGE_MARKER")"
  fi
  if [[ -n "$PREV_IMAGE_IDENTITY" && "$PREV_IMAGE_IDENTITY" != "$CURRENT_IMAGE_IDENTITY" ]]; then
    echo "Image changed; resetting bundled WinePrefix to avoid stale runtime state." >&2
    echo "  previous: $PREV_IMAGE_IDENTITY" >&2
    echo "  current : $CURRENT_IMAGE_IDENTITY" >&2
    rm -rf "$HOST_PREFIX_PATH"
  fi
fi

if [[ -n "$CURRENT_IMAGE_IDENTITY" ]]; then
  printf '%s\n' "$CURRENT_IMAGE_IDENTITY" > "$STATE_IMAGE_MARKER"
fi

ARGS=("$@")
prepare_workspace_dirs_from_args "${ARGS[@]}"
ARGS_Q="$(printf '%q ' "${ARGS[@]}")"

echo "Running DEE under FEX bundled image: $IMAGE_TAG"
# Filter known harmless fontconfig noise from minimal/bundled image while preserving all other stderr lines.
docker run --rm --platform linux/arm64 \
  -v "$STATE_DIR:/state" \
  -v "$ROOT_DIR:/workspace" \
  -v "$DEE_DIR:/workspace/dolby_encoding_engine:ro" \
  "$IMAGE_TAG" bash -lc "
    set -euo pipefail

    # WINEPREFIX dosdevices 设置（ARM64 bash 直接操作，无需进入 FEX 环境）
    mkdir -p '$WINEPREFIX/drive_c' '$WINEPREFIX/dosdevices'
    ln -sfn ../drive_c            '$WINEPREFIX/dosdevices/c:'
    ln -sfn '$FEX_ROOTFS_IN_IMAGE' '$WINEPREFIX/dosdevices/z:'
    ln -sfn /workspace             '$WINEPREFIX/dosdevices/y:'

    # wineboot 首次初始化（FEX /bin/bash：x86-64 bash 上下文，child exec 被 FEX 正确拦截）
    if [[ ! -f '$WINEPREFIX/.dee_fex_bundled_ready' ]]; then
      if timeout '$WINEBOOT_TIMEOUT' \
        FEX /bin/bash -c 'WINEPREFIX=$WINEPREFIX WINEDEBUG=fixme-all $WINE_BIN wineboot.exe -u' >/dev/null 2>&1; then
        touch '$WINEPREFIX/.dee_fex_bundled_ready'
      else
        echo 'wineboot initialization failed in bundled FEX image' >&2
        exit 1
      fi
    fi

    exec FEX /bin/bash -c 'WINEPREFIX=$WINEPREFIX WINEDEBUG=fixme-all $WINE_BIN $DEE_WIN_EXE $ARGS_Q'
  " 2> >(grep -vFx "Fontconfig error: Cannot load default config file: No such file: (null)" >&2)
