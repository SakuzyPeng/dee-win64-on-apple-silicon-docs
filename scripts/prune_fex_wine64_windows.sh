#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/tmp_fex_rootfs/RootFS/Ubuntu_24_04}"
TARGET_DIR="${TARGET_DIR:-$ROOTFS_DIR/usr/lib/x86_64-linux-gnu/wine/x86_64-windows}"
BACKUP_BASE="${BACKUP_BASE:-$ROOT_DIR/tmp_fex_rootfs/Wine64WindowsBackup}"
LOG_GLOB="${LOG_GLOB:-$ROOT_DIR/tmp_bench/loaddll_whitelist/*.log}"
WHITELIST_FILE="${WHITELIST_FILE:-$ROOT_DIR/tmp_fex_rootfs/wine64_windows_whitelist.txt}"

usage() {
  cat <<'EOF'
Usage:
  scripts/prune_fex_wine64_windows.sh --collect [--whitelist FILE]
  scripts/prune_fex_wine64_windows.sh --status [--whitelist FILE]
  scripts/prune_fex_wine64_windows.sh --apply [--whitelist FILE]
  scripts/prune_fex_wine64_windows.sh --rollback [--backup-dir DIR]

Description:
  Prune wine x86_64-windows modules using a whitelist.
  Whitelist is collected from +loaddll logs and merged with an essential keep set.
  --apply moves removable files to backup for reversible rollback.

Environment:
  ROOTFS_DIR       Rootfs path (default: tmp_fex_rootfs/RootFS/Ubuntu_24_04)
  TARGET_DIR       Wine PE dir (default: .../x86_64-windows)
  BACKUP_BASE      Backup base dir (default: tmp_fex_rootfs/Wine64WindowsBackup)
  LOG_GLOB         Log glob for --collect (default: tmp_bench/loaddll_whitelist/*.log)
  WHITELIST_FILE   Whitelist path (default: tmp_fex_rootfs/wine64_windows_whitelist.txt)
EOF
}

MODE=""
BACKUP_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --collect) MODE="collect" ;;
    --status) MODE="status" ;;
    --apply) MODE="apply" ;;
    --rollback) MODE="rollback" ;;
    --whitelist)
      shift
      WHITELIST_FILE="${1:-}"
      ;;
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
[[ -d "$TARGET_DIR" ]] || { echo "Target dir not found: $TARGET_DIR" >&2; exit 1; }

latest_backup_dir() {
  [[ -d "$BACKUP_BASE" ]] || return 1
  find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1
}

normalize_whitelist() {
  src="$1"
  dst="$2"
  tr '[:upper:]' '[:lower:]' < "$src" | sed '/^$/d' | sort -u > "$dst"
}

is_kept() {
  local base lc
  base="$(basename "$1")"
  lc="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
  grep -Fxq "$lc" "$WHITELIST_NORM"
}

collect_mode() {
  tmp_src="$(mktemp)"
  tmp_norm="$(mktemp)"
  trap 'rm -f "$tmp_src" "$tmp_norm"' EXIT

  # Parse builtin modules loaded from C:\windows\system32\... in +loaddll logs.
  # Keep only basename in lowercase.
  matched=0
  for f in $LOG_GLOB; do
    [[ -f "$f" ]] || continue
    matched=1
    rg -o -i 'Loaded L"C:\\\\windows\\\\system32\\\\[^"]+".*: builtin' "$f" \
      | sed -E 's/.*system32\\\\([^"\\]+)".*/\1/I' \
      | tr '[:upper:]' '[:lower:]' \
      >> "$tmp_src" || true
  done

  if [[ "$matched" == "0" ]]; then
    echo "No logs matched LOG_GLOB=$LOG_GLOB" >&2
  fi

  cat <<'EOF' >> "$tmp_src"
ntdll.dll
apisetschema.dll
winedevice.exe
ntoskrnl.exe
wineboot.exe
services.exe
cmd.exe
conhost.exe
explorer.exe
rundll32.exe
reg.exe
regedit.exe
start.exe
winemenubuilder.exe
EOF

  mkdir -p "$(dirname "$WHITELIST_FILE")"
  normalize_whitelist "$tmp_src" "$tmp_norm"
  cp "$tmp_norm" "$WHITELIST_FILE"
  echo "Whitelist written: $WHITELIST_FILE"
  echo "Whitelist entries: $(wc -l < "$WHITELIST_FILE" | awk '{print $1}')"
}

status_mode() {
  [[ -f "$WHITELIST_FILE" ]] || {
    echo "Whitelist missing: $WHITELIST_FILE"
    echo "Run: scripts/prune_fex_wine64_windows.sh --collect"
    exit 1
  }

  WHITELIST_NORM="$(mktemp)"
  trap 'rm -f "$WHITELIST_NORM"' EXIT
  normalize_whitelist "$WHITELIST_FILE" "$WHITELIST_NORM"

  total_files=0
  keep_files=0
  remove_files=0
  keep_kb=0
  remove_kb=0

  while IFS= read -r -d '' file; do
    total_files=$((total_files + 1))
    kb="$(du -sk "$file" | awk '{print $1}')"
    if is_kept "$file"; then
      keep_files=$((keep_files + 1))
      keep_kb=$((keep_kb + kb))
    else
      remove_files=$((remove_files + 1))
      remove_kb=$((remove_kb + kb))
    fi
  done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)

  echo "Target dir: $TARGET_DIR"
  echo "Whitelist: $WHITELIST_FILE"
  echo "Total files      : $total_files"
  echo "Keep files       : $keep_files"
  echo "Removable files  : $remove_files"
  echo "Keep size (KB)   : $keep_kb"
  echo "Remove size (KB) : $remove_kb"

  if latest="$(latest_backup_dir 2>/dev/null)"; then
    echo "Latest backup: $latest"
  else
    echo "No backup found under: $BACKUP_BASE"
  fi
}

apply_mode() {
  [[ -f "$WHITELIST_FILE" ]] || {
    echo "Whitelist missing: $WHITELIST_FILE"
    echo "Run: scripts/prune_fex_wine64_windows.sh --collect"
    exit 1
  }

  WHITELIST_NORM="$(mktemp)"
  trap 'rm -f "$WHITELIST_NORM"' EXIT
  normalize_whitelist "$WHITELIST_FILE" "$WHITELIST_NORM"

  mkdir -p "$BACKUP_BASE"
  local_ts="$(date +%Y%m%d_%H%M%S)"
  BACKUP_DIR="$BACKUP_BASE/$local_ts"
  mkdir -p "$BACKUP_DIR"
  manifest="$BACKUP_DIR/MANIFEST.txt"
  : > "$manifest"
  cp "$WHITELIST_FILE" "$BACKUP_DIR/WHITELIST.txt"

  before_kb="$(du -sk "$TARGET_DIR" | awk '{print $1}')"
  moved_any=0
  moved_files=0

  while IFS= read -r -d '' file; do
    if is_kept "$file"; then
      continue
    fi
    base="$(basename "$file")"
    mv "$file" "$BACKUP_DIR/$base"
    echo "$base" >> "$manifest"
    moved_any=1
    moved_files=$((moved_files + 1))
  done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)

  if [[ "$moved_any" == "0" ]]; then
    echo "Nothing pruned. All files already in whitelist."
    rm -f "$manifest"
    rm -f "$BACKUP_DIR/WHITELIST.txt"
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    exit 0
  fi

  after_kb="$(du -sk "$TARGET_DIR" | awk '{print $1}')"
  saved_kb=$((before_kb - after_kb))
  echo "Backup dir: $BACKUP_DIR"
  echo "Moved files      : $moved_files"
  echo "Target size before: ${before_kb} KB"
  echo "Target size after : ${after_kb} KB"
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
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    src="$BACKUP_DIR/$name"
    dst="$TARGET_DIR/$name"
    [[ -e "$src" ]] || continue
    if [[ -e "$dst" ]]; then
      rm -f "$dst"
    fi
    mv "$src" "$dst"
    restored=$((restored + 1))
  done < "$manifest"

  echo "Rollback complete from: $BACKUP_DIR"
  echo "Restored files: $restored"
}

case "$MODE" in
  collect) collect_mode ;;
  status) status_mode ;;
  apply) apply_mode ;;
  rollback) rollback_mode ;;
  *) usage >&2; exit 2 ;;
esac
