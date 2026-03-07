#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/tmp_fex_rootfs/RootFS/Ubuntu_24_04}"
KEEP_LOCALES="${KEEP_LOCALES:-en en_US}"
APPLY=0

usage() {
  cat <<'EOF'
Usage:
  scripts/prune_fex_rootfs.sh [--apply]

Description:
  Prune low-risk runtime-irrelevant files in FEX rootfs.
  Default mode is dry-run (show reclaimable size only).

Options:
  --apply    Actually delete files.
  -h,--help  Show help.

Environment:
  ROOTFS_DIR    Rootfs directory (default: tmp_fex_rootfs/RootFS/Ubuntu_24_04)
  KEEP_LOCALES  Space-separated locale dirs to keep (default: "en en_US")
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! -d "$ROOTFS_DIR" ]]; then
  echo "RootFS directory not found: $ROOTFS_DIR" >&2
  exit 1
fi

TARGETS=(
  "usr/share/doc"
  "usr/share/man"
  "usr/share/info"
  "usr/share/lintian"
  "usr/share/bug"
  "var/cache/apt/archives"
  "var/lib/apt/lists"
  "var/log"
  "tmp"
  "var/tmp"
)

sum_kb=0
print_target() {
  local rel="$1"
  local path="$ROOTFS_DIR/$rel"
  [[ -e "$path" ]] || return 0
  local kb
  kb="$(du -sk "$path" | awk '{print $1}')"
  echo "$kb KB  $rel"
  sum_kb=$((sum_kb + kb))
}

echo "RootFS: $ROOTFS_DIR"
echo "Mode: $([[ "$APPLY" == "1" ]] && echo "apply" || echo "dry-run")"
echo ""
echo "Prune candidates:"
for rel in "${TARGETS[@]}"; do
  print_target "$rel"
done

LOCALE_DIR="$ROOTFS_DIR/usr/share/locale"
locale_kb=0
locale_count=0
if [[ -d "$LOCALE_DIR" ]]; then
  while IFS= read -r d; do
    base="$(basename "$d")"
    keep=0
    for k in $KEEP_LOCALES; do
      [[ "$base" == "$k" ]] && keep=1 && break
    done
    [[ "$keep" == "1" ]] && continue
    kb="$(du -sk "$d" | awk '{print $1}')"
    locale_kb=$((locale_kb + kb))
    locale_count=$((locale_count + 1))
    echo "$kb KB  usr/share/locale/$base"
  done < <(find "$LOCALE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

sum_kb=$((sum_kb + locale_kb))
echo ""
echo "Estimated reclaimable size: $sum_kb KB"

if [[ "$APPLY" != "1" ]]; then
  echo "Dry-run only. Re-run with --apply to prune."
  exit 0
fi

echo ""
echo "Applying prune..."
for rel in "${TARGETS[@]}"; do
  path="$ROOTFS_DIR/$rel"
  [[ -e "$path" ]] || continue
  rm -rf "$path"
done

if [[ -d "$LOCALE_DIR" ]]; then
  while IFS= read -r d; do
    base="$(basename "$d")"
    keep=0
    for k in $KEEP_LOCALES; do
      [[ "$base" == "$k" ]] && keep=1 && break
    done
    [[ "$keep" == "1" ]] && continue
    rm -rf "$d"
  done < <(find "$LOCALE_DIR" -mindepth 1 -maxdepth 1 -type d)
fi

before_kb="$sum_kb"
after_kb="$(du -sk "$ROOTFS_DIR" | awk '{print $1}')"
echo "Prune complete."
echo "RootFS size now: $after_kb KB"
echo "Estimated reclaimed: $before_kb KB"
