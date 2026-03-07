#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${MODE:-both}" # fex | native | both
RUNS="${RUNS:-3}" # repeat count for statistics
FEX_WINEPREFIX="${FEX_WINEPREFIX:-/root/.fex-emu/WinePrefixes/bench_fex}"
NATIVE_WINEPREFIX="${NATIVE_WINEPREFIX:-$ROOT_DIR/tmp_bench/native_wineprefix}"
XML_TEMPLATE_REL="dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml"

BENCH_ROOT="$ROOT_DIR/tmp_bench"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$BENCH_ROOT/$RUN_ID"
RESULTS_TSV="$RUN_DIR/results.tsv"
AGGREGATE_TSV="$RUN_DIR/aggregate.tsv"
SUMMARY_MD="$RUN_DIR/summary.md"

mkdir -p "$RUN_DIR" "$BENCH_ROOT/fex/tmp" "$BENCH_ROOT/native/tmp"
printf "run\tmode\tcase\texit\treal_s\tuser_s\tsys_s\tdee_job_s\tstdout_log\ttime_log\n" > "$RESULTS_TSV"

add_result() {
  local run_idx="$1"
  local mode="$2"
  local case_name="$3"
  local exit_code="$4"
  local real_s="$5"
  local user_s="$6"
  local sys_s="$7"
  local dee_job_s="$8"
  local stdout_log="$9"
  local time_log="${10}"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$run_idx" "$mode" "$case_name" "$exit_code" "$real_s" "$user_s" "$sys_s" "$dee_job_s" "$stdout_log" "$time_log" \
    >> "$RESULTS_TSV"
}

run_case() {
  local run_idx="$1"
  local mode="$2"
  local case_name="$3"
  local cmd="$4"
  local iter_dir="$5"

  local stdout_log="$iter_dir/${mode}_${case_name}.stdout.log"
  local time_log="$iter_dir/${mode}_${case_name}.time.log"
  local exit_code real_s user_s sys_s dee_job_s

  echo "[run $run_idx/$RUNS] $mode::$case_name"
  set +e
  /usr/bin/time -p bash -lc "$cmd" >"$stdout_log" 2>"$time_log"
  exit_code=$?
  set -e

  real_s="$(awk '$1=="real"{print $2}' "$time_log" | tail -n1)"
  user_s="$(awk '$1=="user"{print $2}' "$time_log" | tail -n1)"
  sys_s="$(awk '$1=="sys"{print $2}' "$time_log" | tail -n1)"
  dee_job_s="$(grep -Eo 'Job execution took [0-9]+' "$stdout_log" | awk '{print $4}' | tail -n1 || true)"

  [[ -n "$real_s" ]] || real_s="-"
  [[ -n "$user_s" ]] || user_s="-"
  [[ -n "$sys_s" ]] || sys_s="-"
  [[ -n "$dee_job_s" ]] || dee_job_s="-"

  add_result "$run_idx" "$mode" "$case_name" "$exit_code" "$real_s" "$user_s" "$sys_s" "$dee_job_s" "$stdout_log" "$time_log"
}

skip_case() {
  local run_idx="$1"
  local mode="$2"
  local case_name="$3"
  local reason="$4"
  local iter_dir="$5"

  local stdout_log="$iter_dir/${mode}_${case_name}.stdout.log"
  local time_log="$iter_dir/${mode}_${case_name}.time.log"
  printf "SKIPPED: %s\n" "$reason" > "$stdout_log"
  : > "$time_log"
  add_result "$run_idx" "$mode" "$case_name" "SKIP" "-" "-" "-" "-" "$stdout_log" "$time_log"
}

run_fex() {
  local run_idx="$1"
  local iter_dir="$2"

  if [[ ! -x "$ROOT_DIR/scripts/run_dee_with_fex.sh" ]]; then
    skip_case "$run_idx" "fex" "help_cold" "scripts/run_dee_with_fex.sh not found" "$iter_dir"
    skip_case "$run_idx" "fex" "help_warm" "scripts/run_dee_with_fex.sh not found" "$iter_dir"
    skip_case "$run_idx" "fex" "encode_adm_to_ec3" "scripts/run_dee_with_fex.sh not found" "$iter_dir"
    return
  fi

  run_case "$run_idx" "fex" "help_cold" \
    "cd '$ROOT_DIR' && rm -rf '$ROOT_DIR/tmp_fex_rootfs/WinePrefixes/bench_fex' && WINEPREFIX='$FEX_WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --help" \
    "$iter_dir"

  run_case "$run_idx" "fex" "help_warm" \
    "cd '$ROOT_DIR' && WINEPREFIX='$FEX_WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --help" \
    "$iter_dir"

  run_case "$run_idx" "fex" "encode_adm_to_ec3" \
    "cd '$ROOT_DIR' && WINEPREFIX='$FEX_WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --xml 'y:/$XML_TEMPLATE_REL' --input-audio 'y:/testADM.wav' --output 'y:/tmp_bench/fex/testADM_baseline.ec3' --temp 'y:/tmp_bench/fex/tmp' --log-file 'y:/tmp_bench/fex/dee_encode.log' --stdout --verbose info" \
    "$iter_dir"
}

run_native() {
  local run_idx="$1"
  local iter_dir="$2"

  if ! command -v wine64 >/dev/null 2>&1; then
    skip_case "$run_idx" "native" "help_cold" "wine64 not found in PATH" "$iter_dir"
    skip_case "$run_idx" "native" "help_warm" "wine64 not found in PATH" "$iter_dir"
    skip_case "$run_idx" "native" "encode_adm_to_ec3" "wine64 not found in PATH" "$iter_dir"
    return
  fi

  if [[ ! -f "$ROOT_DIR/dolby_encoding_engine/dee.exe" ]]; then
    skip_case "$run_idx" "native" "help_cold" "dolby_encoding_engine/dee.exe not found" "$iter_dir"
    skip_case "$run_idx" "native" "help_warm" "dolby_encoding_engine/dee.exe not found" "$iter_dir"
    skip_case "$run_idx" "native" "encode_adm_to_ec3" "dolby_encoding_engine/dee.exe not found" "$iter_dir"
    return
  fi

  run_case "$run_idx" "native" "help_cold" \
    "cd '$ROOT_DIR' && rm -rf '$NATIVE_WINEPREFIX' && WINEPREFIX='$NATIVE_WINEPREFIX' wine64 '$ROOT_DIR/dolby_encoding_engine/dee.exe' --help" \
    "$iter_dir"

  run_case "$run_idx" "native" "help_warm" \
    "cd '$ROOT_DIR' && WINEPREFIX='$NATIVE_WINEPREFIX' wine64 '$ROOT_DIR/dolby_encoding_engine/dee.exe' --help" \
    "$iter_dir"

  run_case "$run_idx" "native" "encode_adm_to_ec3" \
    "cd '$ROOT_DIR' && WINEPREFIX='$NATIVE_WINEPREFIX' wine64 '$ROOT_DIR/dolby_encoding_engine/dee.exe' --xml '$ROOT_DIR/$XML_TEMPLATE_REL' --input-audio '$ROOT_DIR/testADM.wav' --output '$ROOT_DIR/tmp_bench/native/testADM_baseline.ec3' --temp '$ROOT_DIR/tmp_bench/native/tmp' --log-file '$ROOT_DIR/tmp_bench/native/dee_encode.log' --stdout --verbose info" \
    "$iter_dir"
}

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid RUNS=$RUNS (expected positive integer)" >&2
  exit 2
fi

for run_idx in $(seq 1 "$RUNS"); do
  ITER_DIR="$RUN_DIR/run_$(printf '%02d' "$run_idx")"
  mkdir -p "$ITER_DIR"

  case "$MODE" in
    fex) run_fex "$run_idx" "$ITER_DIR" ;;
    native) run_native "$run_idx" "$ITER_DIR" ;;
    both)
      run_fex "$run_idx" "$ITER_DIR"
      run_native "$run_idx" "$ITER_DIR"
      ;;
    *)
      echo "Invalid MODE=$MODE (expected: fex|native|both)" >&2
      exit 2
      ;;
  esac
done

AGGREGATE_TMP="$RUN_DIR/aggregate.raw.tsv"

awk -F'\t' '
function fmt(v) { return (v == "-" ? "-" : sprintf("%.3f", v)) }
NR == 1 { next }
{
  key = $2 FS $3
  runs[key]++
  if ($4 == "0") ok[key]++

  if ($5 ~ /^[0-9]+([.][0-9]+)?$/) {
    real = $5 + 0
    real_n[key]++
    real_sum[key] += real
    real_sq[key] += (real * real)
    if (!(key in real_min) || real < real_min[key]) real_min[key] = real
    if (!(key in real_max) || real > real_max[key]) real_max[key] = real
  }

  if ($8 ~ /^[0-9]+([.][0-9]+)?$/) {
    job = $8 + 0
    job_n[key]++
    job_sum[key] += job
  }
}
END {
  print "mode\tcase\truns\tsuccess\tmean_real_s\tstd_real_s\tmin_real_s\tmax_real_s\tmean_dee_job_s"
  for (key in runs) {
    split(key, parts, FS)
    mode = parts[1]
    case_name = parts[2]

    mean_real = "-"
    std_real = "-"
    min_real = "-"
    max_real = "-"
    mean_job = "-"

    if (real_n[key] > 0) {
      mean_real = real_sum[key] / real_n[key]
      min_real = real_min[key]
      max_real = real_max[key]
      if (real_n[key] > 1) {
        variance = (real_sq[key] - (real_sum[key] * real_sum[key] / real_n[key])) / (real_n[key] - 1)
        if (variance < 0) variance = 0
        std_real = sqrt(variance)
      } else {
        std_real = 0
      }
    }

    if (job_n[key] > 0) {
      mean_job = job_sum[key] / job_n[key]
    }

    printf "%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\n", \
      mode, case_name, runs[key], ok[key] + 0, \
      fmt(mean_real), fmt(std_real), fmt(min_real), fmt(max_real), fmt(mean_job)
  }
}
' "$RESULTS_TSV" > "$AGGREGATE_TMP"

{
  head -n1 "$AGGREGATE_TMP"
  tail -n +2 "$AGGREGATE_TMP" | sort -t $'\t' -k1,1 -k2,2
} > "$AGGREGATE_TSV"

{
  echo "# Baseline Summary"
  echo ""
  echo "- Run ID: \`$RUN_ID\`"
  echo "- Mode: \`$MODE\`"
  echo "- Runs: \`$RUNS\`"
  echo ""
  echo "## Aggregate"
  echo ""
  echo "| mode | case | runs | success | mean_real_s | std_real_s | min_real_s | max_real_s | mean_dee_job_s |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---:|"
  tail -n +2 "$AGGREGATE_TSV" | while IFS=$'\t' read -r mode case_name runs success mean_real std_real min_real max_real mean_job; do
    echo "| $mode | $case_name | $runs | $success | $mean_real | $std_real | $min_real | $max_real | $mean_job |"
  done
  echo ""
  echo "## Per-Run"
  echo ""
  echo "| run | mode | case | exit | real_s | user_s | sys_s | dee_job_s | stdout_log |"
  echo "|---:|---|---|---:|---:|---:|---:|---:|---|"
  tail -n +2 "$RESULTS_TSV" | sort -t $'\t' -k1,1n -k2,2 -k3,3 | while IFS=$'\t' read -r run_idx mode case_name exit_code real_s user_s sys_s dee_job_s stdout_log _; do
    echo "| $run_idx | $mode | $case_name | $exit_code | $real_s | $user_s | $sys_s | $dee_job_s | \`$stdout_log\` |"
  done
  echo ""
} > "$SUMMARY_MD"

echo "Baseline finished."
echo "Summary: $SUMMARY_MD"
echo "Raw results: $RESULTS_TSV"
echo "Aggregate: $AGGREGATE_TSV"
cat "$SUMMARY_MD"
