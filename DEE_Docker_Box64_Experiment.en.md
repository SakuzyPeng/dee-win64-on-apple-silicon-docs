# DEE Box64 Container Guide (ARM64)

## Goal
Add a third parallel `box64` container track on Apple Silicon for DEE CLI encoding workloads, maintained as a release-candidate path.

Positioning of `box64`:
- Runs in parallel with `FEX` and `Rosetta 2` tracks
- Prioritizes functional stability and portability before performance optimization

## Track Definition
### Path A (preferred target)
- `linux/arm64` base image
- `box64 + wine64:amd64` (multiarch)
- Run `dee.exe` directly

### Path B (fallback plan)
- If Path A cannot pass `ADM -> EC3` acceptance within one iteration window
- Switch to `amd64` userland RootFS + box64
- No disruption to existing FEX/Rosetta2 flows

> The repository currently runs Path A: build a modern `box64` inside the `linux/arm64` container and execute multiarch `wine64:amd64` directly.

## Path A Recovery Log (historical blocker -> current status)
- Date: 2026-03-08
- Path A observed blockers:
  - `wine: could not load kernel32.dll, status c0000135`
  - high noise from `nodrv_CreateWindow` / `explorer.exe /desktop` in headless runs
  - insufficient startup stability for `--help/--print-stages` under cold/parallel conditions
- Fix: upgrade from the old distro `box64` package to a modern source-built `box64`; Path A now passes `--help/--print-stages/ADM->EC3/5x stability` acceptance.
- Outcome: keep Path B as emergency fallback, but default release target is Path A again.

## Key Scripts
- `scripts/build_box64_lab.sh`
- `scripts/run_box64_lab_probe.sh`
- `scripts/run_dee_with_box64.sh`
- `scripts/benchmark_box64_baseline.sh`
- `scripts/acceptance_box64_candidate.sh`

## One-Time Setup
1. Build the lab image
```bash
./scripts/build_box64_lab.sh
```

2. Probe box64/wine runtime basics
```bash
./scripts/run_box64_lab_probe.sh
```

## Daily Use
CLI smoke:
```bash
./scripts/run_dee_with_box64.sh --help
```

`print-stages`:
```bash
./scripts/run_dee_with_box64.sh \
  --print-stages \
  -l y:/dolby_encoding_engine/license.lic
```

ADM sample encode:
```bash
./scripts/run_dee_with_box64.sh \
  --xml y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml \
  --input-audio y:/testADM.wav \
  --output y:/tmp_box64_acceptance/manual/testADM.ec3 \
  --temp y:/tmp_box64_acceptance/manual/tmp \
  --log-file y:/tmp_box64_acceptance/manual/dee.log \
  -l y:/dolby_encoding_engine/license.lic \
  --stdout \
  --verbose info
```

## Runtime Conventions
`run_dee_with_box64.sh` already handles:
- `WINEPREFIX` initialization
- drive mapping
- `c:` -> `../drive_c`
- `z:` -> `/`
- `y:` -> `/workspace`
- one-time `wineboot -u`
- auto-create host directories for `y:/...` `--temp/--log-file/--output`

Default state directory:
- `tmp_box64_state/` (rebuildable)

## Acceptance Gate (for release promotion)
1. Smoke:
```bash
./scripts/run_dee_with_box64.sh --help
./scripts/run_dee_with_box64.sh --print-stages -l y:/dolby_encoding_engine/license.lic
```

2. Real encode: `ADM -> EC3` succeeds, output and log files exist, exit code `0`

3. Stability: same encode command succeeds 5/5 times
```bash
./scripts/acceptance_box64_candidate.sh
```

4. Baseline capture (no performance gate in this phase):
```bash
./scripts/benchmark_box64_baseline.sh
```

## GHCR Publishing Policy
Image name:
- `ghcr.io/sakuzypeng/dee-box64-lab`

Tag policy:
- candidate: `candidate-YYYYMMDD-HHMMSS`
- dated: `vYYYY.MM.DD`
- stable: `latest` (promote only after full acceptance)

Example:
```bash
docker tag dee-box64-lab:local ghcr.io/sakuzypeng/dee-box64-lab:candidate-$(date +%Y%m%d-%H%M%S)
docker tag dee-box64-lab:local ghcr.io/sakuzypeng/dee-box64-lab:v$(date +%Y.%m.%d)
docker push ghcr.io/sakuzypeng/dee-box64-lab:candidate-$(date +%Y%m%d-%H%M%S)
docker push ghcr.io/sakuzypeng/dee-box64-lab:v$(date +%Y.%m.%d)
# Promote latest only after acceptance passes
```

## Common Notes
1. The current image builds modern `box64` from source inside the container and installs multiarch `wine64:amd64`.
2. `nodrv_CreateWindow`-style logs are usually harmless for headless CLI runs.
3. DEE requires `--temp` to exist; the wrapper auto-creates host directories for `y:/...`.
4. If storage gets tight, clean `tmp_box64_state*` and old benchmark output directories.
