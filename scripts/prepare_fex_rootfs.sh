#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROOTFS_BASE="${ROOTFS_BASE:-$ROOT_DIR/tmp_fex_rootfs}"
ROOTFS_STORE="$ROOTFS_BASE/RootFS"
META_URL="${META_URL:-https://rootfs.fex-emu.gg/RootFS_links.json}"

DISTRO_MATCH="${DISTRO_MATCH:-ubuntu}"
DISTRO_VERSION="${DISTRO_VERSION:-24.04}"
FS_TYPE="${FS_TYPE:-squashfs}"

EXTRACT="${EXTRACT:-1}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-0}"

mkdir -p "$ROOTFS_STORE"

echo "Fetching RootFS metadata: $META_URL"
JSON="$(curl -fsSL "$META_URL")"

ROOTFS_URL="$(
  jq -r \
    --arg d "$DISTRO_MATCH" \
    --arg v "$DISTRO_VERSION" \
    --arg t "$FS_TYPE" \
    '
      .v1
      | to_entries[]
      | select(.value.DistroMatch == $d and .value.DistroVersion == $v and .value.Type == $t)
      | .value.URL
    ' <<<"$JSON" | head -n 1
)"

if [[ -z "$ROOTFS_URL" || "$ROOTFS_URL" == "null" ]]; then
  echo "No RootFS URL found for match=$DISTRO_MATCH version=$DISTRO_VERSION type=$FS_TYPE" >&2
  exit 1
fi

ROOTFS_FILE="$ROOTFS_STORE/$(basename "$ROOTFS_URL")"
ROOTFS_NAME="${ROOTFS_FILE##*/}"
ROOTFS_NAME="${ROOTFS_NAME%.sqsh}"
ROOTFS_NAME="${ROOTFS_NAME%.ero}"
EXTRACT_DIR="$ROOTFS_STORE/$ROOTFS_NAME"

echo "Selected URL: $ROOTFS_URL"
echo "Target file:  $ROOTFS_FILE"

if [[ "$FORCE_DOWNLOAD" == "1" || ! -s "$ROOTFS_FILE" ]]; then
  TMP_FILE="$ROOTFS_FILE.part"
  echo "Downloading RootFS..."
  curl -fL --continue-at - --output "$TMP_FILE" "$ROOTFS_URL"
  mv "$TMP_FILE" "$ROOTFS_FILE"
else
  echo "Reusing existing RootFS file."
fi

if [[ "$EXTRACT" != "1" ]]; then
  echo "Skip extract (EXTRACT=$EXTRACT)."
  echo "ROOTFS_FILE=$ROOTFS_FILE"
  exit 0
fi

if [[ "$FS_TYPE" != "squashfs" ]]; then
  echo "Auto-extract currently supports squashfs only. FS_TYPE=$FS_TYPE" >&2
  echo "ROOTFS_FILE=$ROOTFS_FILE"
  exit 0
fi

if [[ -d "$EXTRACT_DIR/usr" ]]; then
  echo "Reusing extracted directory: $EXTRACT_DIR"
  echo "FEX_ROOTFS=$EXTRACT_DIR"
  exit 0
fi

echo "Extracting squashfs to: $EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
docker run --rm --platform linux/arm64 \
  -v "$ROOTFS_BASE:/data" \
  ubuntu:24.04 bash -lc "
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null
    apt-get install -y --no-install-recommends squashfs-tools >/dev/null
    unsquashfs -f -d '/data/RootFS/$ROOTFS_NAME' '/data/RootFS/$(basename "$ROOTFS_FILE")' >/tmp/unsquash.log
  "

echo "FEX_ROOTFS=$EXTRACT_DIR"
