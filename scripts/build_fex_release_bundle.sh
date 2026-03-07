#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/tmp_fex_rootfs/RootFS/Ubuntu_24_04}"
ENGINE_DIR="${ENGINE_DIR:-$ROOT_DIR/dolby_encoding_engine}"
OUTPUT_BASE="${OUTPUT_BASE:-$ROOT_DIR/release}"
BUNDLE_TAG="${BUNDLE_TAG:-$(date +%Y%m%d_%H%M%S)}"
INCLUDE_ENGINE="${INCLUDE_ENGINE:-0}"
PUBLISH_LATEST="${PUBLISH_LATEST:-1}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  scripts/build_fex_release_bundle.sh [--include-engine] [--no-latest] [--dry-run] [--tag TAG]

Description:
  Build distributable runtime bundle (.tar.zst + .sha256) for FEX workflow.

Defaults:
  - include rootfs + runtime scripts + docs
  - do NOT include dolby_encoding_engine unless --include-engine is set

Environment:
  ROOTFS_DIR    RootFS path (default: tmp_fex_rootfs/RootFS/Ubuntu_24_04)
  ENGINE_DIR    DEE directory (default: dolby_encoding_engine)
  OUTPUT_BASE   Release output base (default: release/)
  BUNDLE_TAG    Bundle tag (default: timestamp)
  PUBLISH_LATEST  Publish stable copy to release/latest (default: 1)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-engine) INCLUDE_ENGINE=1 ;;
    --no-latest) PUBLISH_LATEST=0 ;;
    --dry-run) DRY_RUN=1 ;;
    --tag)
      shift
      BUNDLE_TAG="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

[[ -n "$BUNDLE_TAG" ]] || { echo "Empty BUNDLE_TAG" >&2; exit 2; }
[[ -d "$ROOTFS_DIR" ]] || { echo "RootFS not found: $ROOTFS_DIR" >&2; exit 1; }

if ! command -v zstd >/dev/null 2>&1; then
  echo "zstd not found in PATH. Install zstd first." >&2
  exit 1
fi

if [[ "$INCLUDE_ENGINE" == "1" && ! -d "$ENGINE_DIR" ]]; then
  echo "ENGINE_DIR not found: $ENGINE_DIR" >&2
  exit 1
fi

BUNDLE_NAME="dee-fex-runtime-${BUNDLE_TAG}"
OUT_DIR="$OUTPUT_BASE/$BUNDLE_NAME"
LATEST_DIR="$OUTPUT_BASE/latest"
STAGE_DIR="$ROOT_DIR/tmp_release_stage/$BUNDLE_NAME"
ARCHIVE_PATH="$OUT_DIR/${BUNDLE_NAME}.tar.zst"
SHA_PATH="$OUT_DIR/${BUNDLE_NAME}.sha256"
MANIFEST_PATH="$OUT_DIR/${BUNDLE_NAME}.manifest.txt"
LATEST_ARCHIVE_PATH="$LATEST_DIR/dee-fex-runtime.tar.zst"
LATEST_SHA_PATH="$LATEST_DIR/dee-fex-runtime.sha256"
LATEST_MANIFEST_PATH="$LATEST_DIR/dee-fex-runtime.manifest.txt"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/runtime/scripts" "$STAGE_DIR/runtime/tmp_fex_rootfs/RootFS"
rm -f "$ARCHIVE_PATH" "$SHA_PATH" "$MANIFEST_PATH"

cp "$ROOT_DIR/scripts/run_dee_with_fex.sh" "$STAGE_DIR/runtime/scripts/"
cp "$ROOT_DIR/scripts/run_dee_with_fex_persistent.sh" "$STAGE_DIR/runtime/scripts/"
cp "$ROOT_DIR/scripts/unpack_fex_release_bundle.sh" "$STAGE_DIR/runtime/scripts/"
if cp -cR "$ROOTFS_DIR" "$STAGE_DIR/runtime/tmp_fex_rootfs/RootFS/Ubuntu_24_04" 2>/dev/null; then
  :
else
  cp -R "$ROOTFS_DIR" "$STAGE_DIR/runtime/tmp_fex_rootfs/RootFS/Ubuntu_24_04"
fi

if [[ "$INCLUDE_ENGINE" == "1" ]]; then
  cp -R "$ENGINE_DIR" "$STAGE_DIR/runtime/dolby_encoding_engine"
fi

cat > "$STAGE_DIR/runtime/RELEASE_INFO.txt" <<EOF
BUNDLE_NAME=$BUNDLE_NAME
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
INCLUDE_ENGINE=$INCLUDE_ENGINE
ROOTFS_LAYOUT=tmp_fex_rootfs/RootFS/Ubuntu_24_04
ENGINE_LAYOUT=dolby_encoding_engine
EOF

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry-run complete. Staged at: $STAGE_DIR"
  du -sh "$STAGE_DIR"
  exit 0
fi

(cd "$STAGE_DIR" && tar -cf - runtime) | zstd -19 -T0 --force -o "$ARCHIVE_PATH"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$ARCHIVE_PATH")" > "$(basename "$SHA_PATH")")

{
  echo "BUNDLE_NAME=$BUNDLE_NAME"
  echo "ARCHIVE=$(basename "$ARCHIVE_PATH")"
  echo "SHA256_FILE=$(basename "$SHA_PATH")"
  echo "INCLUDE_ENGINE=$INCLUDE_ENGINE"
  echo "PUBLISH_LATEST=$PUBLISH_LATEST"
  echo ""
  echo "[sizes]"
  du -sh "$ARCHIVE_PATH" | awk '{print "archive="$1}'
  du -sh "$STAGE_DIR/runtime/tmp_fex_rootfs/RootFS/Ubuntu_24_04" | awk '{print "rootfs="$1}'
  if [[ "$INCLUDE_ENGINE" == "1" ]]; then
    du -sh "$STAGE_DIR/runtime/dolby_encoding_engine" | awk '{print "engine="$1}'
  fi
} > "$MANIFEST_PATH"

if [[ "$PUBLISH_LATEST" == "1" ]]; then
  mkdir -p "$LATEST_DIR"
  cp "$ARCHIVE_PATH" "$LATEST_ARCHIVE_PATH"
  (cd "$LATEST_DIR" && shasum -a 256 "$(basename "$LATEST_ARCHIVE_PATH")" > "$(basename "$LATEST_SHA_PATH")")
  {
    echo "BUNDLE_NAME=$BUNDLE_NAME"
    echo "ARCHIVE=$(basename "$LATEST_ARCHIVE_PATH")"
    echo "SHA256_FILE=$(basename "$LATEST_SHA_PATH")"
    echo "SOURCE_DIR=$(basename "$OUT_DIR")"
  } > "$LATEST_MANIFEST_PATH"
fi

rm -rf "$STAGE_DIR"

echo "Release bundle created:"
echo "  Archive : $ARCHIVE_PATH"
echo "  SHA256  : $SHA_PATH"
echo "  Manifest: $MANIFEST_PATH"
du -sh "$ARCHIVE_PATH"
if [[ "$PUBLISH_LATEST" == "1" ]]; then
  echo "Published latest:"
  echo "  Archive : $LATEST_ARCHIVE_PATH"
  echo "  SHA256  : $LATEST_SHA_PATH"
  echo "  Manifest: $LATEST_MANIFEST_PATH"
fi
