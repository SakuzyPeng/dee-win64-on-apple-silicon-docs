#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/tmp_fex_rootfs/RootFS/Ubuntu_24_04}"
BACKUP_BASE="${BACKUP_BASE:-$ROOT_DIR/tmp_fex_rootfs/Wine32Backup}"

TARGETS=(
  "usr/lib/i386-linux-gnu/wine"
  "usr/lib/wine/i386-unix"
  "usr/lib/wine/i386-windows"
  "usr/lib/wine/wine"
  "usr/lib/wine/wineserver32"
)

usage() {
  cat <<'EOF'
Usage:
  scripts/prune_fex_wine32.sh --apply
  scripts/prune_fex_wine32.sh --rollback [--backup-dir DIR]
  scripts/prune_fex_wine32.sh --status

Environment:
  ROOTFS_DIR   Rootfs path (default: tmp_fex_rootfs/RootFS/Ubuntu_24_04)
  BACKUP_BASE  Backup base dir (default: tmp_fex_rootfs/Wine32Backup)
EOF
}

MODE=""
BACKUP_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply" ;;
    --rollback) MODE="rollback" ;;
    --status) MODE="status" ;;
    --backup-dir)
      shift
      BACKUP_DIR="${1:-}"
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

[[ -n "$MODE" ]] || { usage >&2; exit 2; }
[[ -d "$ROOTFS_DIR" ]] || { echo "RootFS not found: $ROOTFS_DIR" >&2; exit 1; }

latest_backup_dir() {
  [[ -d "$BACKUP_BASE" ]] || return 1
  find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1
}

status_mode() {
  echo "RootFS: $ROOTFS_DIR"
  for rel in "${TARGETS[@]}"; do
    if [[ -e "$ROOTFS_DIR/$rel" ]]; then
      du -sh "$ROOTFS_DIR/$rel" 2>/dev/null || true
    else
      echo "missing  $rel"
    fi
  done

  echo ""
  if latest="$(latest_backup_dir 2>/dev/null)"; then
    echo "Latest backup: $latest"
    find "$latest" -type f -name MANIFEST.txt -print -exec cat {} \;
  else
    echo "No backup found under: $BACKUP_BASE"
  fi
}

apply_mode() {
  mkdir -p "$BACKUP_BASE"
  local_ts="$(date +%Y%m%d_%H%M%S)"
  BACKUP_DIR="${BACKUP_BASE}/${local_ts}"
  mkdir -p "$BACKUP_DIR"
  manifest="$BACKUP_DIR/MANIFEST.txt"
  : > "$manifest"

  before_kb="$(du -sk "$ROOTFS_DIR" | awk '{print $1}')"
  moved_any=0
  for rel in "${TARGETS[@]}"; do
    src="$ROOTFS_DIR/$rel"
    [[ -e "$src" ]] || continue
    dst="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
    echo "$rel" >> "$manifest"
    moved_any=1
    echo "moved: $rel"
  done

  if [[ "$moved_any" == "0" ]]; then
    echo "No wine32 targets found. Nothing changed."
    rm -f "$manifest"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    exit 0
  fi

  after_kb="$(du -sk "$ROOTFS_DIR" | awk '{print $1}')"
  saved_kb=$((before_kb - after_kb))
  echo "Backup dir: $BACKUP_DIR"
  echo "RootFS size before: ${before_kb} KB"
  echo "RootFS size after : ${after_kb} KB"
  echo "Reclaimed approx  : ${saved_kb} KB"
}

rollback_mode() {
  if [[ -z "$BACKUP_DIR" ]]; then
    BACKUP_DIR="$(latest_backup_dir || true)"
  fi
  [[ -n "$BACKUP_DIR" ]] || { echo "No backup dir found." >&2; exit 1; }
  [[ -d "$BACKUP_DIR" ]] || { echo "Backup dir missing: $BACKUP_DIR" >&2; exit 1; }
  manifest="$BACKUP_DIR/MANIFEST.txt"
  [[ -f "$manifest" ]] || { echo "Manifest missing: $manifest" >&2; exit 1; }

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$BACKUP_DIR/$rel"
    dst="$ROOTFS_DIR/$rel"
    [[ -e "$src" ]] || continue
    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" ]]; then
      rm -rf "$dst"
    fi
    mv "$src" "$dst"
    echo "restored: $rel"
  done < "$manifest"

  echo "Rollback complete from: $BACKUP_DIR"
}

case "$MODE" in
  apply) apply_mode ;;
  rollback) rollback_mode ;;
  status) status_mode ;;
  *) usage >&2; exit 2 ;;
esac
