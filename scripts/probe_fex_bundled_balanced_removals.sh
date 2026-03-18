#!/usr/bin/env bash
# probe_fex_bundled_balanced_removals.sh
# Probe removable wine builtins from balanced image by dropping one file per derived image.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_IMAGE="${BASE_IMAGE:-dee-fex-bundled:phase2-balanced-v4}"
PLATFORM="${PLATFORM:-linux/arm64}"
RUNS="${RUNS:-1}"
KEEP_IMAGES="${KEEP_IMAGES:-0}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/tmp_fex_bundled_probe_balanced}"
RESULTS_TSV="$OUT_DIR/results.tsv"
SUMMARY_MD="$OUT_DIR/summary.md"
STATE_BASE="$OUT_DIR/state"
FEX_ROOTFS_PATH="${FEX_ROOTFS_PATH:-/root/.fex-emu/RootFS/Ubuntu_24_04}"

# Candidate filenames under wine/x86_64-windows
CANDIDATES=(
  msacm.imaadpcm
  msacm.l3acm
  msacm.msadpcm
  msacm.msg711
  msacm.msgsm610
  sane.ds
  winemac.drv
  winex11.drv
  start.exe
)

usage() {
  cat <<'USAGE'
Usage:
  scripts/probe_fex_bundled_balanced_removals.sh [options]

Options:
  --base-image TAG   base balanced image tag (default: dee-fex-bundled:phase2-balanced-v4)
  --runs N           gate encode runs per probe (default: 1)
  --keep-images      keep derived probe images (default: remove)
  --out-dir DIR      output directory
  -h, --help         show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-image)
      shift
      BASE_IMAGE="${1:-}"
      ;;
    --runs)
      shift
      RUNS="${1:-}"
      ;;
    --keep-images)
      KEEP_IMAGES=1
      ;;
    --out-dir)
      shift
      OUT_DIR="${1:-}"
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

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid --runs: $RUNS" >&2
  exit 2
fi

if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  echo "Base image not found: $BASE_IMAGE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$STATE_BASE"

printf "candidate\tbase_exists\tderived_image\tbuild_ok\tgate_ok\tencode_mean_real\timage_size_gib\tsummary\n" > "$RESULTS_TSV"

sanitize_tag() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-'
}

extract_summary_field() {
  local summary_file="$1"
  local field="$2"
  awk -F'`' -v k="$field" 'index($0, k) > 0 {print $2}' "$summary_file" | tail -n1
}

echo "Base image: $BASE_IMAGE"
echo "Probing ${#CANDIDATES[@]} candidate(s)..."

for candidate in "${CANDIDATES[@]}"; do
  candidate_path="$FEX_ROOTFS_PATH/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/$candidate"
  probe_tag="dee-fex-bundled:probe-$(sanitize_tag "$candidate")"
  probe_state="$STATE_BASE/$(sanitize_tag "$candidate")"

  echo ""
  echo "== Probe: $candidate =="
  echo "Build derived image: $probe_tag"

  base_exists=0
  build_ok=1
  gate_ok=0
  encode_mean="-"
  image_size_gib="-"
  summary_path="-"

  if docker run --rm --platform "$PLATFORM" "$BASE_IMAGE" \
    bash -lc "test -f '$candidate_path'" >/dev/null 2>&1; then
    base_exists=1
  fi

  set +e
  docker build \
    --platform "$PLATFORM" \
    --tag "$probe_tag" \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    --build-arg CANDIDATE_PATH="$candidate_path" \
    -f - "$ROOT_DIR" >/dev/null <<'DOCKERFILE'
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}
ARG CANDIDATE_PATH
RUN rm -f "$CANDIDATE_PATH"
DOCKERFILE
  rc_build=$?
  set -e

  if [[ $rc_build -ne 0 ]]; then
    build_ok=0
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$candidate" "$base_exists" "$probe_tag" "$build_ok" "$gate_ok" "$encode_mean" "$image_size_gib" "$summary_path" \
      >> "$RESULTS_TSV"
    echo "Build failed: $candidate"
    continue
  fi

  gate_log="$OUT_DIR/$(sanitize_tag "$candidate").gate.log"
  set +e
  IMAGE_TAG="$probe_tag" \
    RUNS="$RUNS" \
    STATE_DIR="$probe_state" \
    "$ROOT_DIR/scripts/benchmark_fex_bundled_gate.sh" >"$gate_log" 2>&1
  rc_gate=$?
  set -e
  gate_output="$(cat "$gate_log")"

  summary_path="$(printf '%s\n' "$gate_output" | awk -F': ' '/^Gate summary:/ {print $2}' | tail -n1)"
  if [[ -f "$summary_path" ]]; then
    encode_mean="$(extract_summary_field "$summary_path" 'Encode mean real (s)')"
    image_size_gib="$(extract_summary_field "$summary_path" 'Image size (GiB)')"
  fi

  if [[ $rc_gate -eq 0 ]]; then
    gate_ok=1
    echo "Gate PASS: $candidate"
  else
    gate_ok=0
    echo "Gate FAIL: $candidate"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$candidate" "$base_exists" "$probe_tag" "$build_ok" "$gate_ok" "$encode_mean" "$image_size_gib" "$summary_path" \
    >> "$RESULTS_TSV"

  if [[ "$KEEP_IMAGES" != "1" ]]; then
    docker image rm "$probe_tag" >/dev/null 2>&1 || true
  fi
done

pass_count="$(awk -F'\t' 'NR>1 && $5==1 {n++} END{print n+0}' "$RESULTS_TSV")"
fail_count="$(awk -F'\t' 'NR>1 && ($4==0 || $5==0) {n++} END{print n+0}' "$RESULTS_TSV")"

{
  echo "# FEX Bundled Balanced Removal Probe"
  echo ""
  echo "- Base image: \`$BASE_IMAGE\`"
  echo "- Runs per probe: \`$RUNS\`"
  echo "- Candidate count: \`${#CANDIDATES[@]}\`"
  echo "- Gate pass: \`$pass_count\`"
  echo "- Gate fail/build fail: \`$fail_count\`"
  echo ""
  echo "| candidate | base_exists | build_ok | gate_ok | encode_mean_real | image_size_gib | summary |"
  echo "|---|---:|---:|---:|---:|---:|---|"
  tail -n +2 "$RESULTS_TSV" | awk -F'\t' '{printf "| %s | %s | %s | %s | %s | %s | `%s` |\n", $1, $2, $4, $5, $6, $7, $8}'
} > "$SUMMARY_MD"

echo ""
echo "Probe finished."
echo "Results: $RESULTS_TSV"
echo "Summary: $SUMMARY_MD"
