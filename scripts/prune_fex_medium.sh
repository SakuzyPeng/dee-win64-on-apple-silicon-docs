#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/tmp_fex_rootfs/RootFS/Ubuntu_24_04}"
BACKUP_BASE="${BACKUP_BASE:-$ROOT_DIR/tmp_fex_rootfs/MediumPruneBackup}"

TARGETS=(
  "usr/lib/python3"
  "usr/lib/python3.12"
  "usr/lib/x86_64-linux-gnu/perl"
  "usr/lib/x86_64-linux-gnu/perl-base"
  "usr/share/perl"
  "usr/share/cmake-3.28"
  "usr/bin/cmake"
  "usr/bin/cpack"
  "usr/bin/ctest"
  "usr/bin/git"
  "usr/lib/git-core"
  "usr/share/icons"
  "usr/share/gtk-3.0"
  "usr/share/gtk-4.0"
  "usr/share/X11"
)

usage() {
  cat <<'EOF'
Usage:
  scripts/prune_fex_medium.sh --status
  scripts/prune_fex_medium.sh --apply
  scripts/prune_fex_medium.sh --rollback [--backup-dir DIR]

Description:
  Medium-risk prune for FEX rootfs:
  - python/perl runtime trees
  - cmake/git tooling
  - icons/gtk/x11 share resources

  --apply moves targets to backup for reversible rollback.

Environment:
  ROOTFS_DIR   Rootfs path (default: tmp_fex_rootfs/RootFS/Ubuntu_24_04)
  BACKUP_BASE  Backup base dir (default: tmp_fex_rootfs/MediumPruneBackup)
EOF
}

MODE=""
BACKUP_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) MODE="status" ;;
    --apply) MODE="apply" ;;
    --rollback) MODE="rollback" ;;
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
  sum_kb=0
  count=0
  echo "RootFS: $ROOTFS_DIR"
  echo "Candidates:"
  for rel in "${TARGETS[@]}"; do
    path="$ROOTFS_DIR/$rel"
    [[ -e "$path" ]] || continue
    kb="$(du -sk "$path" | awk '{print $1}')"
    echo "$kb KB  $rel"
    sum_kb=$((sum_kb + kb))
    count=$((count + 1))
  done

  echo ""
  echo "Candidate count: $count"
  echo "Estimated reclaimable: $sum_kb KB"

  if latest="$(latest_backup_dir 2>/dev/null)"; then
    echo "Latest backup: $latest"
  else
    echo "No backup found under: $BACKUP_BASE"
  fi
}

apply_mode() {
  mkdir -p "$BACKUP_BASE"
  ts="$(date +%Y%m%d_%H%M%S)"
  BACKUP_DIR="$BACKUP_BASE/$ts"
  mkdir -p "$BACKUP_DIR"
  manifest="$BACKUP_DIR/MANIFEST.txt"
  : > "$manifest"

  before_kb="$(du -sk "$ROOTFS_DIR" | awk '{print $1}')"
  moved=0
  for rel in "${TARGETS[@]}"; do
    src="$ROOTFS_DIR/$rel"
    [[ -e "$src" ]] || continue
    dst="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
    echo "$rel" >> "$manifest"
    moved=$((moved + 1))
    echo "moved: $rel"
  done

  if [[ "$moved" -eq 0 ]]; then
    echo "No medium targets found. Nothing changed."
    rm -f "$manifest"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    exit 0
  fi

  after_kb="$(du -sk "$ROOTFS_DIR" | awk '{print $1}')"
  saved_kb=$((before_kb - after_kb))
  echo "Backup dir: $BACKUP_DIR"
  echo "Moved count: $moved"
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

  restored=0
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
    restored=$((restored + 1))
    echo "restored: $rel"
  done < "$manifest"

  echo "Rollback complete from: $BACKUP_DIR"
  echo "Restored count: $restored"
}

case "$MODE" in
  --status|status) status_mode ;;
  --apply|apply) apply_mode ;;
  --rollback|rollback) rollback_mode ;;
  *) usage >&2; exit 2 ;;
esac
