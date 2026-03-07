#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-}"
SHA_PATH="${SHA_PATH:-}"
DEST_DIR="${DEST_DIR:-$ROOT_DIR}"
FORCE=0
VERIFY_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  scripts/unpack_fex_release_bundle.sh [--archive FILE] [--sha256 FILE] [--dest DIR] [--force] [--verify-only]

Description:
  Verify and unpack a FEX runtime release bundle (.tar.zst).

Defaults:
  - --archive: prefer release/latest/dee-fex-runtime.tar.zst, else auto-detect latest release/*.tar.zst
  - --sha256:  auto-detect from archive path (<name>.sha256)
  - --dest:    repository root
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      shift
      ARCHIVE_PATH="${1:-}"
      ;;
    --sha256)
      shift
      SHA_PATH="${1:-}"
      ;;
    --dest)
      shift
      DEST_DIR="${1:-}"
      ;;
    --force) FORCE=1 ;;
    --verify-only) VERIFY_ONLY=1 ;;
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

if ! command -v zstd >/dev/null 2>&1; then
  echo "zstd not found in PATH. Install zstd first." >&2
  exit 1
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  PREFERRED_ARCHIVE="$ROOT_DIR/release/latest/dee-fex-runtime.tar.zst"
  if [[ -f "$PREFERRED_ARCHIVE" ]]; then
    ARCHIVE_PATH="$PREFERRED_ARCHIVE"
  else
    mapfile -t CANDIDATES < <(find "$ROOT_DIR/release" -type f -name '*.tar.zst' 2>/dev/null | sort)
    if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
      echo "No archive found under: $ROOT_DIR/release" >&2
      echo "Use --archive FILE to specify one." >&2
      exit 1
    fi
    ARCHIVE_PATH="${CANDIDATES[-1]}"
  fi
fi

[[ -f "$ARCHIVE_PATH" ]] || { echo "Archive not found: $ARCHIVE_PATH" >&2; exit 1; }

if [[ -z "$SHA_PATH" ]]; then
  CANDIDATE_SHA="${ARCHIVE_PATH%.tar.zst}.sha256"
  if [[ -f "$CANDIDATE_SHA" ]]; then
    SHA_PATH="$CANDIDATE_SHA"
  fi
fi

if [[ -n "$SHA_PATH" ]]; then
  [[ -f "$SHA_PATH" ]] || { echo "SHA256 file not found: $SHA_PATH" >&2; exit 1; }
  EXPECTED_HASH="$(awk 'NF {print $1; exit}' "$SHA_PATH")"
  ACTUAL_HASH="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
  if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
    echo "SHA256 mismatch for: $ARCHIVE_PATH" >&2
    echo "  expected: $EXPECTED_HASH" >&2
    echo "  actual  : $ACTUAL_HASH" >&2
    exit 1
  fi
  echo "SHA256 verified: $ARCHIVE_PATH"
else
  echo "SHA256 file not provided/found; skip verification."
fi

if [[ "$VERIFY_ONLY" == "1" ]]; then
  exit 0
fi

mkdir -p "$DEST_DIR"

if [[ -e "$DEST_DIR/runtime" ]]; then
  if [[ "$FORCE" == "1" ]]; then
    rm -rf "$DEST_DIR/runtime"
  else
    echo "Target exists: $DEST_DIR/runtime" >&2
    echo "Use --force to overwrite." >&2
    exit 1
  fi
fi

zstd -dc "$ARCHIVE_PATH" | tar -xf - -C "$DEST_DIR"

echo "Unpacked to: $DEST_DIR/runtime"
echo "Run with:"
echo "  bash $DEST_DIR/runtime/scripts/run_dee_with_fex.sh --help"
