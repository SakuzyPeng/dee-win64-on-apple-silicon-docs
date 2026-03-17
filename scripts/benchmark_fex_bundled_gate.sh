#!/usr/bin/env bash
# benchmark_fex_bundled_gate.sh
# Functional + performance + size gate for bundled FEX image.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-dee-fex-bundled:phase2-balanced-v3}"
RUNS="${RUNS:-3}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/tmp_fex_bundled_state_bench}"
WINEPREFIX="${WINEPREFIX:-/state/WinePrefixes/bench_fex_bundled}"

BASELINE_FILE="${BASELINE_FILE:-$ROOT_DIR/configs/fex_bundled_baseline.env}"
if [[ -f "$BASELINE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$BASELINE_FILE"
fi

BASELINE_ENCODE_MEAN="${BASELINE_ENCODE_MEAN:-18.450}"
PERF_LIMIT_RATIO="${PERF_LIMIT_RATIO:-1.05}"
PERF_THRESHOLD_S="${PERF_THRESHOLD_S:-}"
TARGET_IMAGE_SIZE_GB="${TARGET_IMAGE_SIZE_GB:-1.00}"
STRICT_FAIL_REGEX="${STRICT_FAIL_REGEX:-Library ntoskrnl\\.exe .*not found|service L\"Winedevice[0-9]+\" failed to start|Importing dlls for .*winedevice\\.exe failed}"

XML_TEMPLATE_REL="dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml"

BENCH_ROOT="$ROOT_DIR/tmp_bench"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$BENCH_ROOT/$RUN_ID"
RESULTS_TSV="$RUN_DIR/results.tsv"
SUMMARY_MD="$RUN_DIR/summary.md"

usage() {
  cat <<'EOF'
Usage:
  scripts/benchmark_fex_bundled_gate.sh [options]

Options:
  --image TAG      bundled image tag (default: dee-fex-bundled:phase2-balanced-v3)
  --runs N         encode runs (default: 3)
  --state-dir DIR  benchmark state directory
  -h, --help       show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      shift
      IMAGE_TAG="${1:-}"
      ;;
    --runs)
      shift
      RUNS="${1:-}"
      ;;
    --state-dir)
      shift
      STATE_DIR="${1:-}"
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
  echo "Invalid --runs: $RUNS (expected positive integer)" >&2
  exit 2
fi

if [[ ! -x "$ROOT_DIR/scripts/run_dee_with_fex_bundled.sh" ]]; then
  echo "Missing runner: $ROOT_DIR/scripts/run_dee_with_fex_bundled.sh" >&2
  exit 1
fi

if [[ ! -x "$ROOT_DIR/scripts/check_fex_bundled_cold_start.sh" ]]; then
  echo "Missing cold-start checker: $ROOT_DIR/scripts/check_fex_bundled_cold_start.sh" >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/testADM.wav" ]]; then
  echo "Input audio missing: $ROOT_DIR/testADM.wav" >&2
  exit 1
fi

mkdir -p "$RUN_DIR" "$ROOT_DIR/tmp_bench/fex_bundled/tmp"
printf "run\tcase\texit\treal_s\tuser_s\tsys_s\tdee_job_s\tstdout_log\ttime_log\toutput_file\toutput_ok\tprogress_ok\tcritical_sig\n" > "$RESULTS_TSV"

calc_threshold() {
  awk -v b="$BASELINE_ENCODE_MEAN" -v r="$PERF_LIMIT_RATIO" 'BEGIN { printf "%.3f", (b * r) + 0.0005 }'
}

if [[ -n "$PERF_THRESHOLD_S" ]]; then
  THRESHOLD_ENCODE="$PERF_THRESHOLD_S"
else
  THRESHOLD_ENCODE="$(calc_threshold)"
fi

get_image_size_bytes() {
  docker image inspect "$IMAGE_TAG" --format '{{.Size}}' 2>/dev/null || echo "0"
}

to_gib() {
  local bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN { printf "%.3f", b / (1024*1024*1024) }'
}

add_result() {
  local run_idx="$1"
  local case_name="$2"
  local exit_code="$3"
  local real_s="$4"
  local user_s="$5"
  local sys_s="$6"
  local dee_job_s="$7"
  local stdout_log="$8"
  local time_log="$9"
  local output_file="${10}"
  local output_ok="${11}"
  local progress_ok="${12}"
  local critical_sig="${13}"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$run_idx" "$case_name" "$exit_code" "$real_s" "$user_s" "$sys_s" "$dee_job_s" \
    "$stdout_log" "$time_log" "$output_file" "$output_ok" "$progress_ok" "$critical_sig" \
    >> "$RESULTS_TSV"
}

run_case() {
  local run_idx="$1"
  local case_name="$2"
  local cmd="$3"
  local output_file="$4"

  local stdout_log="$RUN_DIR/${case_name}_run${run_idx}.stdout.log"
  local time_log="$RUN_DIR/${case_name}_run${run_idx}.time.log"
  local exit_code real_s user_s sys_s dee_job_s output_ok progress_ok critical_sig

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

  output_ok="NA"
  progress_ok="NA"
  critical_sig="0"
  if [[ -n "$output_file" ]]; then
    if [[ -s "$output_file" ]]; then
      output_ok="1"
    else
      output_ok="0"
    fi
    if grep -q 'Overall progress: 100.0' "$stdout_log"; then
      progress_ok="1"
    else
      progress_ok="0"
    fi
  fi

  if [[ -n "$STRICT_FAIL_REGEX" ]]; then
    if grep -Eiq "$STRICT_FAIL_REGEX" "$stdout_log" "$time_log"; then
      critical_sig="1"
    fi
  fi

  add_result "$run_idx" "$case_name" "$exit_code" "$real_s" "$user_s" "$sys_s" "$dee_job_s" \
    "$stdout_log" "$time_log" "$output_file" "$output_ok" "$progress_ok" "$critical_sig"
}

echo "[1/3] Function checks: help cold/warm"
run_case "1" "help_cold" \
  "cd '$ROOT_DIR' && IMAGE_TAG='$IMAGE_TAG' STATE_DIR='$STATE_DIR' WINEPREFIX='$WINEPREFIX' STRICT_FAIL_REGEX='$STRICT_FAIL_REGEX' '$ROOT_DIR/scripts/check_fex_bundled_cold_start.sh'" \
  ""

run_case "1" "help_warm" \
  "cd '$ROOT_DIR' && IMAGE_TAG='$IMAGE_TAG' STATE_DIR='$STATE_DIR' WINEPREFIX='$WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex_bundled.sh' --help" \
  ""

echo "[2/3] Encode x$RUNS"
for run_idx in $(seq 1 "$RUNS"); do
  output_file="$ROOT_DIR/tmp_bench/fex_bundled/testADM_gate_run${run_idx}.ec3"
  log_file="y:/tmp_bench/fex_bundled/testADM_gate_run${run_idx}.log"
  run_case "$run_idx" "encode_adm_to_ec3" \
    "cd '$ROOT_DIR' && IMAGE_TAG='$IMAGE_TAG' STATE_DIR='$STATE_DIR' WINEPREFIX='$WINEPREFIX' '$ROOT_DIR/scripts/run_dee_with_fex_bundled.sh' --xml 'y:/$XML_TEMPLATE_REL' --input-audio 'y:/testADM.wav' --output 'y:/tmp_bench/fex_bundled/testADM_gate_run${run_idx}.ec3' --temp 'y:/tmp_bench/fex_bundled/tmp' --log-file '$log_file' --stdout --verbose info" \
    "$output_file"
done

encode_mean_real="$(
  awk -F'\t' '
    NR > 1 && $2 == "encode_adm_to_ec3" && $3 == "0" && $4 ~ /^[0-9]+([.][0-9]+)?$/ {
      n++; sum += $4
    }
    END {
      if (n == 0) print "-";
      else printf "%.3f", sum / n
    }
  ' "$RESULTS_TSV"
)"

encode_mean_job="$(
  awk -F'\t' '
    NR > 1 && $2 == "encode_adm_to_ec3" && $3 == "0" && $7 ~ /^[0-9]+([.][0-9]+)?$/ {
      n++; sum += $7
    }
    END {
      if (n == 0) print "-";
      else printf "%.3f", sum / n
    }
  ' "$RESULTS_TSV"
)"

functional_fail_count="$(
  awk -F'\t' '
    NR > 1 {
      if ($2 ~ /^help_/ && $3 != "0") fail++;
      if ($2 == "encode_adm_to_ec3" && ($3 != "0" || $11 != "1" || $12 != "1")) fail++;
      if ($13 == "1") fail++;
    }
    END { print fail + 0 }
  ' "$RESULTS_TSV"
)"

critical_match_count="$(
  awk -F'\t' '
    NR > 1 && $13 == "1" { n++ }
    END { print n + 0 }
  ' "$RESULTS_TSV"
)"

image_size_bytes="$(get_image_size_bytes)"
image_size_gib="$(to_gib "$image_size_bytes")"
size_target_reached="$(
  awk -v cur="$image_size_gib" -v target="$TARGET_IMAGE_SIZE_GB" 'BEGIN { if (cur <= target) print "1"; else print "0" }'
)"

perf_gate="FAIL"
if [[ "$encode_mean_real" != "-" ]]; then
  if awk -v v="$encode_mean_real" -v t="$THRESHOLD_ENCODE" 'BEGIN { exit !(v <= t) }'; then
    perf_gate="PASS"
  fi
fi

func_gate="PASS"
if [[ "$functional_fail_count" != "0" ]]; then
  func_gate="FAIL"
fi

echo "[3/3] Writing summary"
{
  echo "# FEX Bundled Gate Summary"
  echo ""
  echo "- Run ID: \`$RUN_ID\`"
  echo "- Image: \`$IMAGE_TAG\`"
  echo "- Runs: \`$RUNS\`"
  echo "- Baseline file: \`$BASELINE_FILE\`"
  echo "- Baseline encode mean (s): \`$BASELINE_ENCODE_MEAN\`"
  echo "- Perf threshold (+5% by default): \`$THRESHOLD_ENCODE\`"
  echo "- Encode mean real (s): \`$encode_mean_real\`"
  echo "- Encode mean \"Job execution took\" (s): \`$encode_mean_job\`"
  echo "- Image size (GiB): \`$image_size_gib\`"
  echo "- Size target (GiB): \`$TARGET_IMAGE_SIZE_GB\`"
  echo "- Size target reached: \`$size_target_reached\`"
  echo "- Strict fail regex: \`$STRICT_FAIL_REGEX\`"
  echo "- Critical signature matches: \`$critical_match_count\`"
  echo "- Function gate: \`$func_gate\`"
  echo "- Performance gate: \`$perf_gate\`"
  echo ""
  echo "## Per Case"
  echo ""
  echo "| run | case | exit | real_s | user_s | sys_s | dee_job_s | output_ok | progress_ok | critical_sig | stdout_log |"
  echo "|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|"
  tail -n +2 "$RESULTS_TSV" | awk -F'\t' '{ printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | `%s` |\n", $1, $2, $3, $4, $5, $6, $7, $11, $12, $13, $8 }'
  echo ""
} > "$SUMMARY_MD"

echo "Gate summary: $SUMMARY_MD"
cat "$SUMMARY_MD"

if [[ "$func_gate" != "PASS" ]]; then
  echo "Functional gate failed." >&2
  exit 3
fi

if [[ "$perf_gate" != "PASS" ]]; then
  echo "Performance gate failed: encode mean $encode_mean_real > $THRESHOLD_ENCODE" >&2
  exit 4
fi

echo "All gates passed."
