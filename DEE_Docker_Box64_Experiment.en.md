# DEE Box64 Container Guide (ARM64)

## Scope
- Goal: run `dee.exe` on Apple Silicon with `box64 + wine64:amd64`.
- Position: third parallel track alongside FEX and Rosetta2.
- Priority: stable `ADM -> EC3` first, performance tuning later.
- Prune boundary: prune container runtime only, not the DEE payload.

## Prerequisites
- Docker installed (with `linux/arm64` support).
- Repository root contains:
  - `dolby_encoding_engine/dee.exe`
  - `dolby_encoding_engine/license.lic`
  - `testADM.wav`

## Quick Start (full image)
1. Build:
```bash
./scripts/build_box64_lab.sh --profile aggressive
```
2. Probe:
```bash
IMAGE_TAG=dee-box64-lab:local ./scripts/run_box64_lab_probe.sh
```
3. Smoke:
```bash
IMAGE_TAG=dee-box64-lab:local ./scripts/run_dee_with_box64.sh --help
IMAGE_TAG=dee-box64-lab:local ./scripts/run_dee_with_box64.sh --print-stages
```
4. Real encode (ADM -> EC3):
```bash
IMAGE_TAG=dee-box64-lab:local ./scripts/run_dee_with_box64.sh \
  --xml y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml \
  --input-audio y:/testADM.wav \
  --output y:/tmp_box64_acceptance/manual/testADM.ec3 \
  --temp y:/tmp_box64_acceptance/manual/tmp \
  --log-file y:/tmp_box64_acceptance/manual/dee.log \
  -l y:/dolby_encoding_engine/license.lic \
  --stdout --verbose info
```

## Aggressive Pruning (slim image)
1. Generate runtime allowlist (recommended: `encode` mode):
```bash
./scripts/generate_box64_runtime_allowlist.sh \
  --image dee-box64-lab:local \
  --mode encode \
  --out-dir tmp_box64_prune/allowlist
```
2. Build slim:
```bash
./scripts/build_box64_allowlist_slim.sh \
  --source-image dee-box64-lab:local \
  --target-image dee-box64-lab:slim-local \
  --allowlist tmp_box64_prune/allowlist/runtime-allowlist.txt
```
3. Run slim smoke/encode by changing `IMAGE_TAG` to `dee-box64-lab:slim-local`.

Stability guardrail:
- slim keeps full Wine runtime directories:
  - `/usr/lib/wine`
  - `/usr/lib/x86_64-linux-gnu/wine`
  - `/usr/share/wine`
- everything else is allowlist-pruned to avoid regressions from missing critical DLL/EXE assets.

One-shot flow (aggressive + allowlist + slim):
```bash
./scripts/build_box64_lab.sh \
  --profile aggressive \
  --generate-allowlist \
  --allowlist-mode encode \
  --build-slim \
  --slim-tag dee-box64-lab:slim-local
```

## Acceptance Checklist
- Smoke: `--help` and `--print-stages` return `0`.
- Real encode: `ADM WAV -> Atmos DDP EC3` succeeds with output and log files present.
- Stability: same command succeeds `5/5`.
```bash
IMAGE_TAG=dee-box64-lab:slim-local ./scripts/acceptance_box64_candidate.sh
```
- Baseline (compatible with existing output format):
```bash
IMAGE_TAG=dee-box64-lab:slim-local ./scripts/benchmark_box64_baseline.sh
```
- Size report:
```bash
./scripts/report_box64_image_size.sh --image dee-box64-lab:slim-local
```

## Release and Rollback
Image: `ghcr.io/sakuzypeng/dee-box64-lab`

Recommended tags:
- `full-candidate-YYYYMMDD-HHMMSS`
- `slim-candidate-YYYYMMDD-HHMMSS`
- `vYYYY.MM.DD`
- `full-latest`
- `slim-latest`
- `latest` (promote only after full acceptance)

Rules:
- `latest` must point to fully accepted builds only.
- If slim fails acceptance, publish full candidate only with blocker notes.
- Keep both full/slim entry tags for safe rollback.

## Common Notes
1. `nodrv_CreateWindow` in headless mode is usually non-fatal noise.
2. DEE requires `--temp` to exist; wrapper scripts auto-create host dirs for `y:/...`.
3. If storage is tight, clean `tmp_box64_state*`, `tmp_box64_prune/`, and `tmp_bench/`.
