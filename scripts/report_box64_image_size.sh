#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-dee-box64-lab:local}"
PLATFORM="${PLATFORM:-linux/arm64}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/tmp_box64_prune/size-report}"

usage() {
  cat <<'EOF'
Usage:
  scripts/report_box64_image_size.sh [options]

Options:
  --image TAG       image tag to inspect (default: dee-box64-lab:local)
  --out-dir DIR     output directory for reports
  --platform PLAT   docker platform for runtime probe (default: linux/arm64)
  -h, --help        show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      shift
      IMAGE_TAG="${1:-}"
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

mkdir -p "$OUT_DIR"

SIZE_TSV="$OUT_DIR/size-report.tsv"
SIZE_MD="$OUT_DIR/size-report.md"
HISTORY_TSV="$OUT_DIR/layer-history.tsv"
DU_TSV="$OUT_DIR/du-report.tsv"

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "Image not found: $IMAGE_TAG" >&2
  exit 1
fi

image_id="$(docker image inspect --format '{{.Id}}' "$IMAGE_TAG")"
image_bytes="$(docker image inspect --format '{{.Size}}' "$IMAGE_TAG")"

docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE_TAG" > "$HISTORY_TSV"

docker run --rm --platform "$PLATFORM" "$IMAGE_TAG" bash -lc '
  set -euo pipefail
  printf "path\tkb\n"
  if ! command -v du >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
    exit 0
  fi
  for p in \
    /usr/local \
    /usr/local/bin \
    /usr/lib/wine \
    /usr/lib/x86_64-linux-gnu \
    /usr/lib/aarch64-linux-gnu \
    /usr/share \
    /opt/box64-prune; do
    if [[ -e "$p" ]]; then
      kb="$(du -sk "$p" | awk "{print \$1}")"
      printf "%s\t%s\n" "$p" "$kb"
    fi
  done
' > "$DU_TSV"

{
  echo -e "item\tvalue"
  echo -e "image_tag\t$IMAGE_TAG"
  echo -e "image_id\t$image_id"
  echo -e "image_bytes\t$image_bytes"
  awk -F'\t' 'NR>1 { printf "du:%s\t%s\n", $1, $2*1024 }' "$DU_TSV"
} > "$SIZE_TSV"

{
  echo "# Box64 Size Report"
  echo ""
  echo "- Image: \`$IMAGE_TAG\`"
  echo "- Image ID: \`$image_id\`"
  echo "- Total size: \`$(awk -v b="$image_bytes" 'BEGIN{printf "%.2f MiB", b/1024/1024}')\`"
  echo ""
  echo "## Directory Breakdown"
  echo ""
  if [[ "$(wc -l < "$DU_TSV" | tr -d ' ')" -le 1 ]]; then
    echo "_Directory toolchain unavailable in image (du/awk), skipped detailed breakdown._"
  else
    echo "| path | size_mib |"
    echo "|---|---:|"
    awk -F'\t' 'NR>1 { printf "| %s | %.2f |\n", $1, $2/1024 }' "$DU_TSV"
  fi
  echo ""
  echo "## Largest Layers"
  echo ""
  echo "| size | created_by |"
  echo "|---:|---|"
  head -n 12 "$HISTORY_TSV" | while IFS=$'\t' read -r size created_by; do
    created_by="${created_by//|/\\|}"
    echo "| $size | \`$created_by\` |"
  done
  echo ""
  echo "Artifacts:"
  echo "- \`$SIZE_TSV\`"
  echo "- \`$DU_TSV\`"
  echo "- \`$HISTORY_TSV\`"
} > "$SIZE_MD"

echo "Size report generated:"
echo "- $SIZE_MD"
echo "- $SIZE_TSV"
