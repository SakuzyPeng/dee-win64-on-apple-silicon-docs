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

IMAGE_TAG="${IMAGE_TAG:-dee-fex-bundled:phase2-balanced-v4}"
DEE_DIR="${DEE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_fex_bundled_state}"
WINEPREFIX="${WINEPREFIX:-/state/WinePrefixes/dee}"
WINEBOOT_TIMEOUT="${WINEBOOT_TIMEOUT:-120}"
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

echo "Running DEE under FEX bundled image: $IMAGE_TAG"
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
  "
