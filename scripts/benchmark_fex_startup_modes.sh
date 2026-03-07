#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUNS="${RUNS:-5}"
IMAGE_TAG="${IMAGE_TAG:-dee-fex-lab:local}"
ROOTFS_BASE="${ROOTFS_BASE:-$ROOT_DIR/tmp_fex_rootfs}"
STD_PREFIX="${STD_PREFIX:-/root/.fex-emu/WinePrefixes/bench_std_mode}"
PERSIST_PREFIX="${PERSIST_PREFIX:-/root/.fex-emu/WinePrefixes/bench_persist_mode}"
PERSIST_CONTAINER="${PERSIST_CONTAINER:-dee-fex-runner-bench}"

BENCH_ROOT="$ROOT_DIR/tmp_bench"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$BENCH_ROOT/$RUN_ID"
RESULTS_TSV="$RUN_DIR/results.tsv"
SUMMARY_MD="$RUN_DIR/summary.md"

mkdir -p "$RUN_DIR"
printf "mode\tcase\trun\texit\treal_s\tuser_s\tsys_s\tstdout_log\ttime_log\n" > "$RESULTS_TSV"

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid RUNS=$RUNS (expected positive integer)" >&2
  exit 2
fi

add_row() {
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$@" >> "$RESULTS_TSV"
}

measure_once() {
  local mode="$1"
  local case_name="$2"
  local run_idx="$3"
  local cmd="$4"
  local stdout_log="$RUN_DIR/${mode}_${case_name}_run${run_idx}.stdout.log"
  local time_log="$RUN_DIR/${mode}_${case_name}_run${run_idx}.time.log"
  local exit_code real_s user_s sys_s

  set +e
  /usr/bin/time -p bash -lc "$cmd" >"$stdout_log" 2>"$time_log"
  exit_code=$?
  set -e

  real_s="$(awk '$1=="real"{print $2}' "$time_log" | tail -n1)"
  user_s="$(awk '$1=="user"{print $2}' "$time_log" | tail -n1)"
  sys_s="$(awk '$1=="sys"{print $2}' "$time_log" | tail -n1)"

  [[ -n "$real_s" ]] || real_s="-"
  [[ -n "$user_s" ]] || user_s="-"
  [[ -n "$sys_s" ]] || sys_s="-"

  add_row "$mode" "$case_name" "$run_idx" "$exit_code" "$real_s" "$user_s" "$sys_s" "$stdout_log" "$time_log"
}

measure_loop() {
  local mode="$1"
  local case_name="$2"
  local cmd="$3"
  local i

  for i in $(seq 1 "$RUNS"); do
    echo "[$mode] $case_name run $i/$RUNS"
    measure_once "$mode" "$case_name" "$i" "$cmd"
  done
}

PERSIST_SCRIPT="$ROOT_DIR/scripts/run_dee_with_fex_persistent.sh"

if [[ ! -x "$ROOT_DIR/scripts/run_dee_with_fex.sh" ]]; then
  echo "Missing script: $ROOT_DIR/scripts/run_dee_with_fex.sh" >&2
  exit 1
fi

if [[ ! -x "$PERSIST_SCRIPT" ]]; then
  echo "Missing script: $PERSIST_SCRIPT" >&2
  exit 1
fi

# Standard mode: cold
measure_once "standard" "help_cold" "1" \
  "cd '$ROOT_DIR' && rm -rf '$ROOT_DIR/tmp_fex_rootfs/WinePrefixes/bench_std_mode' && WINEPREFIX='$STD_PREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --help"

# Standard mode: warm (prime once, then measure RUNS times)
bash -lc "cd '$ROOT_DIR' && WINEPREFIX='$STD_PREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --help >/dev/null 2>&1 || true"
measure_loop "standard" "help_warm" \
  "cd '$ROOT_DIR' && WINEPREFIX='$STD_PREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --help"

# Persistent mode: cold (fresh container + fresh prefix)
bash -lc "cd '$ROOT_DIR' && CONTAINER_NAME='$PERSIST_CONTAINER' '$PERSIST_SCRIPT' stop >/dev/null 2>&1 || true"
measure_once "persistent" "help_cold" "1" \
  "cd '$ROOT_DIR' && rm -rf '$ROOT_DIR/tmp_fex_rootfs/WinePrefixes/bench_persist_mode' && CONTAINER_NAME='$PERSIST_CONTAINER' IMAGE_TAG='$IMAGE_TAG' ROOTFS_BASE='$ROOTFS_BASE' WINEPREFIX='$PERSIST_PREFIX' '$PERSIST_SCRIPT' run --help"

# Persistent mode: warm (container stays up; measure RUNS times)
bash -lc "cd '$ROOT_DIR' && CONTAINER_NAME='$PERSIST_CONTAINER' IMAGE_TAG='$IMAGE_TAG' ROOTFS_BASE='$ROOTFS_BASE' WINEPREFIX='$PERSIST_PREFIX' '$PERSIST_SCRIPT' run --help >/dev/null 2>&1 || true"
measure_loop "persistent" "help_warm" \
  "cd '$ROOT_DIR' && CONTAINER_NAME='$PERSIST_CONTAINER' IMAGE_TAG='$IMAGE_TAG' ROOTFS_BASE='$ROOTFS_BASE' WINEPREFIX='$PERSIST_PREFIX' '$PERSIST_SCRIPT' run --help"

# Cleanup persistent runner
bash -lc "cd '$ROOT_DIR' && CONTAINER_NAME='$PERSIST_CONTAINER' '$PERSIST_SCRIPT' stop >/dev/null 2>&1 || true"

awk -F'\t' '
function fmt(v) { return sprintf("%.3f", v) }
NR == 1 { next }
{
  key = $1 FS $2
  runs[key]++
  if ($4 == "0") ok[key]++
  if ($5 ~ /^[0-9]+([.][0-9]+)?$/) {
    x = $5 + 0
    n[key]++
    sum[key] += x
    sq[key] += x * x
    if (!(key in minv) || x < minv[key]) minv[key] = x
    if (!(key in maxv) || x > maxv[key]) maxv[key] = x
  }
}
END {
  print "mode\tcase\truns\tsuccess\tmean_real_s\tstd_real_s\tmin_real_s\tmax_real_s"
  for (key in runs) {
    split(key, p, FS)
    mean = sum[key] / n[key]
    std = (n[key] > 1) ? sqrt((sq[key] - (sum[key] * sum[key] / n[key])) / (n[key] - 1)) : 0
    printf "%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\n", p[1], p[2], runs[key], ok[key] + 0, fmt(mean), fmt(std), fmt(minv[key]), fmt(maxv[key])
  }
}
' "$RESULTS_TSV" | sort -t $'\t' -k1,1 -k2,2 > "$RUN_DIR/aggregate.tsv"

{
  echo "# FEX Startup Mode Comparison"
  echo ""
  echo "- Run ID: \`$RUN_ID\`"
  echo "- Runs (warm): \`$RUNS\`"
  echo ""
  echo "| mode | case | runs | success | mean_real_s | std_real_s | min_real_s | max_real_s |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|"
  tail -n +2 "$RUN_DIR/aggregate.tsv" | while IFS=$'\t' read -r mode case_name runs success mean std minv maxv; do
    echo "| $mode | $case_name | $runs | $success | $mean | $std | $minv | $maxv |"
  done
} > "$SUMMARY_MD"

echo "Benchmark finished."
echo "Summary: $SUMMARY_MD"
echo "Raw: $RESULTS_TSV"
cat "$SUMMARY_MD"
