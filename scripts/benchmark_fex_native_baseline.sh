#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${MODE:-both}" # fex | native | both
FEX_WINEPREFIX="${FEX_WINEPREFIX:-/root/.fex-emu/WinePrefixes/bench_fex}"
NATIVE_WINEPREFIX="${NATIVE_WINEPREFIX:-$ROOT_DIR/tmp_bench/native_wineprefix}"
XML_TEMPLATE_REL="dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml"

BENCH_ROOT="$ROOT_DIR/tmp_bench"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$BENCH_ROOT/$RUN_ID"
RESULTS_TSV="$RUN_DIR/results.tsv"
SUMMARY_MD="$RUN_DIR/summary.md"

mkdir -p "$RUN_DIR" "$BENCH_ROOT/fex/tmp" "$BENCH_ROOT/native/tmp"
printf "mode\tcase\texit\treal_s\tuser_s\tsys_s\tdee_job_s\tstdout_log\ttime_log\n" > "$RESULTS_TSV"

add_result() {
  local mode="$1"
  local case_name="$2"
  local exit_code="$3"
  local real_s="$4"
  local user_s="$5"
  local sys_s="$6"
  local dee_job_s="$7"
  local stdout_log="$8"
  local time_log="$9"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$mode" "$case_name" "$exit_code" "$real_s" "$user_s" "$sys_s" "$dee_job_s" "$stdout_log" "$time_log" \
    >> "$RESULTS_TSV"
}

run_case() {
  local mode="$1"
  local case_name="$2"
  local cmd="$3"

  local stdout_log="$RUN_DIR/${mode}_${case_name}.stdout.log"
  local time_log="$RUN_DIR/${mode}_${case_name}.time.log"
  local exit_code real_s user_s sys_s dee_job_s

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

  add_result "$mode" "$case_name" "$exit_code" "$real_s" "$user_s" "$sys_s" "$dee_job_s" "$stdout_log" "$time_log"
}

skip_case() {
  local mode="$1"
  local case_name="$2"
  local reason="$3"
  local stdout_log="$RUN_DIR/${mode}_${case_name}.stdout.log"
  local time_log="$RUN_DIR/${mode}_${case_name}.time.log"
  printf "SKIPPED: %s\n" "$reason" > "$stdout_log"
  : > "$time_log"
  add_result "$mode" "$case_name" "SKIP" "-" "-" "-" "-" "$stdout_log" "$time_log"
}

run_fex() {
  if [[ ! -x "$ROOT_DIR/scripts/run_dee_with_fex.sh" ]]; then
    skip_case "fex" "help_cold" "scripts/run_dee_with_fex.sh not found"
    skip_case "fex" "help_warm" "scripts/run_dee_with_fex.sh not found"
    skip_case "fex" "encode_adm_to_ec3" "scripts/run_dee_with_fex.sh not found"
    return
  fi

  run_case "fex" "help_cold" \
    "cd '$ROOT_DIR' && rm -rf '$ROOT_DIR/tmp_fex_rootfs/WinePrefixes/bench_fex' && WINEPREFIX='$FEX_WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --help"

  run_case "fex" "help_warm" \
    "cd '$ROOT_DIR' && WINEPREFIX='$FEX_WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --help"

  run_case "fex" "encode_adm_to_ec3" \
    "cd '$ROOT_DIR' && WINEPREFIX='$FEX_WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex.sh' --xml 'y:/$XML_TEMPLATE_REL' --input-audio 'y:/testADM.wav' --output 'y:/tmp_bench/fex/testADM_baseline.ec3' --temp 'y:/tmp_bench/fex/tmp' --log-file 'y:/tmp_bench/fex/dee_encode.log' --stdout --verbose info"
}

run_native() {
  if ! command -v wine64 >/dev/null 2>&1; then
    skip_case "native" "help_cold" "wine64 not found in PATH"
    skip_case "native" "help_warm" "wine64 not found in PATH"
    skip_case "native" "encode_adm_to_ec3" "wine64 not found in PATH"
    return
  fi

  if [[ ! -f "$ROOT_DIR/dolby_encoding_engine/dee.exe" ]]; then
    skip_case "native" "help_cold" "dolby_encoding_engine/dee.exe not found"
    skip_case "native" "help_warm" "dolby_encoding_engine/dee.exe not found"
    skip_case "native" "encode_adm_to_ec3" "dolby_encoding_engine/dee.exe not found"
    return
  fi

  run_case "native" "help_cold" \
    "cd '$ROOT_DIR' && rm -rf '$NATIVE_WINEPREFIX' && WINEPREFIX='$NATIVE_WINEPREFIX' wine64 '$ROOT_DIR/dolby_encoding_engine/dee.exe' --help"

  run_case "native" "help_warm" \
    "cd '$ROOT_DIR' && WINEPREFIX='$NATIVE_WINEPREFIX' wine64 '$ROOT_DIR/dolby_encoding_engine/dee.exe' --help"

  run_case "native" "encode_adm_to_ec3" \
    "cd '$ROOT_DIR' && WINEPREFIX='$NATIVE_WINEPREFIX' wine64 '$ROOT_DIR/dolby_encoding_engine/dee.exe' --xml '$ROOT_DIR/$XML_TEMPLATE_REL' --input-audio '$ROOT_DIR/testADM.wav' --output '$ROOT_DIR/tmp_bench/native/testADM_baseline.ec3' --temp '$ROOT_DIR/tmp_bench/native/tmp' --log-file '$ROOT_DIR/tmp_bench/native/dee_encode.log' --stdout --verbose info"
}

case "$MODE" in
  fex) run_fex ;;
  native) run_native ;;
  both)
    run_fex
    run_native
    ;;
  *)
    echo "Invalid MODE=$MODE (expected: fex|native|both)" >&2
    exit 2
    ;;
esac

{
  echo "# Baseline Summary"
  echo ""
  echo "- Run ID: \`$RUN_ID\`"
  echo "- Mode: \`$MODE\`"
  echo ""
  echo "| mode | case | exit | real_s | user_s | sys_s | dee_job_s | stdout_log |"
  echo "|---|---|---:|---:|---:|---:|---:|---|"
  tail -n +2 "$RESULTS_TSV" | while IFS=$'\t' read -r mode case_name exit_code real_s user_s sys_s dee_job_s stdout_log _; do
    echo "| $mode | $case_name | $exit_code | $real_s | $user_s | $sys_s | $dee_job_s | \`$stdout_log\` |"
  done
} > "$SUMMARY_MD"

echo "Baseline finished."
echo "Summary: $SUMMARY_MD"
echo "Raw results: $RESULTS_TSV"
cat "$SUMMARY_MD"
