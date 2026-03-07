# DEE FEX Container Guide (ARM64)

## Goal
This guide documents a reproducible `FEX + Wine + linux/arm64` workflow for running DEE CLI encoding jobs on Apple Silicon, with a migration-friendly distribution flow.

Strategic reason for using FEX: reduce dependency on `Rosetta 2` and prepare for a possible future deprecation of `Rosetta 2` by Apple.

Scope:
- CLI-only encoding workloads (no GUI dependency)
- Container-first migration strategy
- Release bundle excludes `dolby_encoding_engine` by default

Out of scope:
- Historical experiment logs and per-run benchmark history
- Generic Wine-only alternatives

## Current Status (2026-03-07)
- `dee.exe --help` works, exit code `0`
- Real encoding `ADM -> Atmos DDP EC3` works, exit code `0`
- `TSO Emulation: Enabled`
- FEX/Wine thunks present (`libarm64ecfex.dll`, `libwow64fex.dll`, `GuestThunks`)

## Key Scripts
Setup and runtime:
- `scripts/build_fex_lab.sh`
- `scripts/prepare_fex_rootfs.sh`
- `scripts/install_wine_in_fex_rootfs_chroot.sh`
- `scripts/run_fex_lab_probe.sh`
- `scripts/run_dee_with_fex.sh`
- `scripts/run_dee_with_fex_persistent.sh`

Pruning:
- `scripts/prune_fex_conservative.sh`
- `scripts/prune_fex_medium.sh`
- `scripts/prune_fex_aggressive.sh`

Release:
- `scripts/build_fex_release_bundle.sh`
- `scripts/unpack_fex_release_bundle.sh`

## One-Time Setup
1. Build the lab image
```bash
./scripts/build_fex_lab.sh
```

2. Prepare RootFS (downloads and extracts Ubuntu 24.04)
```bash
./scripts/prepare_fex_rootfs.sh
```

3. Install Wine inside RootFS and fix runtime layout
```bash
./scripts/install_wine_in_fex_rootfs_chroot.sh
```

4. Run baseline probe
```bash
./scripts/run_fex_lab_probe.sh
```

## Daily Usage
CLI smoke test:
```bash
./scripts/run_dee_with_fex.sh --help
```

ADM sample encode:
```bash
./scripts/run_dee_with_fex.sh \
  --xml y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml \
  --input-audio y:/testADM.wav \
  --output y:/testADM_fex_atmos.ec3 \
  --temp y:/tmp_dee \
  --log-file y:/testADM_fex_atmos.log \
  --stdout \
  --verbose info
```

## Runtime Conventions (Critical)
`run_dee_with_fex.sh` already handles:
- `WINEPREFIX` initialization
- Drive mappings
- `c:` -> `../drive_c`
- `z:` -> `FEX_ROOTFS`
- `y:` -> `/workspace`
- First-run `wineboot -u`

Typical failure when mappings are broken:
- `could not load kernel32.dll, status c0000135`

## Distribution and Migration
### Build release bundle (DEE excluded by default)
```bash
./scripts/build_fex_release_bundle.sh --tag local_test
```

Outputs:
- `release/dee-fex-runtime-local_test/`
- `release/latest/` (stable publish directory)

Stable filenames in `release/latest/`:
- `dee-fex-runtime.tar.zst`
- `dee-fex-runtime.sha256`
- `dee-fex-runtime.manifest.txt`

Optional: include local DEE engine (internal distribution only)
```bash
./scripts/build_fex_release_bundle.sh --include-engine --tag with_engine
```

### Unpack and verify
```bash
./scripts/unpack_fex_release_bundle.sh \
  --archive release/latest/dee-fex-runtime.tar.zst \
  --sha256 release/latest/dee-fex-runtime.sha256 \
  --dest /tmp/dee-fex-runtime-test
```

If DEE is not included in the bundle, pass local engine path at runtime:
```bash
DEE_DIR=/abs/path/to/dolby_encoding_engine \
  bash /tmp/dee-fex-runtime-test/runtime/scripts/run_dee_with_fex.sh --help
```

## Validation Checklist
1. Smoke tests
```bash
./scripts/run_dee_with_fex.sh --help
./scripts/run_dee_with_fex.sh --print-stages
```

2. Real encode
- `ADM -> EC3` succeeds
- output file and log file are present

3. TSO check
```bash
docker run --rm --platform linux/arm64 dee-fex-lab:local \
  bash -lc 'FEXGetConfig --tso-emulation-info'
```
Expected: `TSO Emulation: Enabled`

4. Thunks check
```bash
docker run --rm --platform linux/arm64 dee-fex-lab:local \
  bash -lc 'ls -l /usr/lib/wine/aarch64-windows/libarm64ecfex.dll /usr/lib/wine/aarch64-windows/libwow64fex.dll'
```
Also verify:
- `/usr/share/fex-emu/GuestThunks`
- `/usr/share/fex-emu/GuestThunks_32`
- `/usr/share/fex-emu/ThunksDB.json`

## Size Baseline (DEE Excluded, 2026-03-07)
- Release bundle: `release/latest/dee-fex-runtime.tar.zst` about `150M`
- Unpacked RootFS: about `573M`
- Runtime image: `dee-fex-lab:local` about `632MB`
- Full local runtime footprint (image + RootFS): about `1.2GB`

## Pruning Strategy (Recommended)
Recommended order: `conservative -> medium -> aggressive`

Commands:
```bash
./scripts/prune_fex_conservative.sh --apply
./scripts/prune_fex_medium.sh --apply
./scripts/prune_fex_aggressive.sh --apply
```

Run the validation checklist after each pruning step. Use each script's `--rollback` when needed.

Notes:
- `aggressive` gives the smallest size but may introduce slight performance regression
- If runtime stability/perf is preferred, stop at `medium`

## Known Issues
1. `FEXRootFSFetcher` may fail in non-interactive tty contexts
2. `--as-is` depends on FUSE and is usually unavailable in standard containers
3. `nodrv_CreateWindow` logs are usually harmless for CLI workloads
4. XML templates with `PATH/FILE_NAME` placeholders must be explicitly overridden
5. If packaging fails with `No space left on device`, clean `tmp_release_stage/` and old `release/*` artifacts

## Maintenance Rule
- This file is an operator guide and keeps only executable workflow + acceptance criteria
- Historical experiment details should be tracked via Git history
