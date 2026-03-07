#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_SCRIPT="${RUN_SCRIPT:-$ROOT_DIR/scripts/run_dee_with_box64.sh}"
REPEAT="${REPEAT:-5}"
OUT_BASE="${OUT_BASE:-$ROOT_DIR/tmp_box64_acceptance}"

XML_PATH="y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml"
INPUT_PATH="y:/testADM.wav"
LICENSE_PATH="y:/dolby_encoding_engine/license.lic"

if [[ ! -x "$RUN_SCRIPT" ]]; then
  echo "Run script not found or not executable: $RUN_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/dolby_encoding_engine/dee.exe" ]]; then
  echo "DEE executable not found: $ROOT_DIR/dolby_encoding_engine/dee.exe" >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/testADM.wav" ]]; then
  echo "Input audio not found: $ROOT_DIR/testADM.wav" >&2
  exit 1
fi

mkdir -p "$OUT_BASE"

echo "[1/4] help smoke test"
"$RUN_SCRIPT" --help >/dev/null

echo "[2/4] print-stages smoke test"
"$RUN_SCRIPT" --print-stages -l "$LICENSE_PATH" >/dev/null

echo "[3/4] single real encode"
SINGLE_DIR="$OUT_BASE/single"
mkdir -p "$SINGLE_DIR/tmp"
"$RUN_SCRIPT" \
  --xml "$XML_PATH" \
  --input-audio "$INPUT_PATH" \
  --output "y:/tmp_box64_acceptance/single/testADM.ec3" \
  --temp "y:/tmp_box64_acceptance/single/tmp" \
  --log-file "y:/tmp_box64_acceptance/single/dee.log" \
  -l "$LICENSE_PATH" \
  --stdout --verbose info >/dev/null
test -s "$SINGLE_DIR/testADM.ec3"
test -s "$SINGLE_DIR/dee.log"

echo "[4/4] repeat encode stability test (target: $REPEAT/$REPEAT)"
ok_count=0
for i in $(seq 1 "$REPEAT"); do
  run_dir="$OUT_BASE/repeat_$i"
  mkdir -p "$run_dir/tmp"
  if "$RUN_SCRIPT" \
      --xml "$XML_PATH" \
      --input-audio "$INPUT_PATH" \
      --output "y:/tmp_box64_acceptance/repeat_$i/testADM.ec3" \
      --temp "y:/tmp_box64_acceptance/repeat_$i/tmp" \
      --log-file "y:/tmp_box64_acceptance/repeat_$i/dee.log" \
      -l "$LICENSE_PATH" \
      --stdout --verbose info >/dev/null; then
    if [[ -s "$run_dir/testADM.ec3" && -s "$run_dir/dee.log" ]]; then
      ok_count=$((ok_count + 1))
    fi
  fi
done

echo "Stability result: $ok_count/$REPEAT successful runs"
if [[ "$ok_count" -ne "$REPEAT" ]]; then
  echo "Acceptance failed: expected $REPEAT/$REPEAT successful runs" >&2
  exit 1
fi

echo "Box64 candidate acceptance passed."
