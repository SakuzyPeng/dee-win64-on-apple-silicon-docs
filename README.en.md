# DEE on macOS (Apple Silicon): Running Win x64 Workflow Notes

This repository documents and reproduces a practical setup for running Dolby Encoding Engine (Windows x64) on Apple Silicon macOS via `gcenx/wine`.

Note: the `FEX` container track is used to reduce dependency on `Rosetta 2` and prepare for a potential future deprecation of `Rosetta 2` by Apple.

## Read Me in Chinese

- 中文 README: [README.md](./README.md)
- Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)
- Licenses: [LICENSE](./LICENSE), [LICENSE-docs](./LICENSE-docs)

## Container Quick Start (GHCR)

> GitHub Packages renders the repository README; use the image-specific entry points below.
> Compatibility note (global): validated with a Dolby Media Encoder (GUI) built-in CLI subset (`dee_ddpjoc_encoder.exe`, `dee_ddp_encoder.exe`, `dee_convert_sample_rate.exe`, `mp4muxer.exe`, `mp4demuxer.exe`) across Box64/FEX/Rosetta2 containers and non-container `wine64`; this is not a claim that all Dolby Media Encoder tools are fully verified.

### 1) FEX track (reduce dependency on Rosetta 2)

- Image: `ghcr.io/sakuzypeng/dee-fex-lab:latest`
- Pull:
  ```bash
  docker pull ghcr.io/sakuzypeng/dee-fex-lab:latest
  ```
- Quick smoke test:
  ```bash
  IMAGE_TAG=ghcr.io/sakuzypeng/dee-fex-lab:latest ./scripts/run_dee_with_fex.sh --help
  ```
- Guide: [DEE_Docker_FEX_Experiment.en.md](./DEE_Docker_FEX_Experiment.en.md)

### 2) Box64 track (parallel third path, stable release)

- Image: `ghcr.io/sakuzypeng/dee-box64-lab:latest`
- Pull:
  ```bash
  docker pull ghcr.io/sakuzypeng/dee-box64-lab:latest
  ```
- Quick smoke test:
  ```bash
  IMAGE_TAG=ghcr.io/sakuzypeng/dee-box64-lab:latest ./scripts/run_dee_with_box64.sh --help
  ```
- Guide: [DEE_Docker_Box64_Experiment.en.md](./DEE_Docker_Box64_Experiment.en.md)
- Rollback-safe tags: `full-latest`, `slim-latest` (`latest` always points to the most recently fully accepted build)

### 3) Rosetta 2 track (non-FEX compatibility path)

- Image: `ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest`
- Pull:
  ```bash
  docker pull ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest
  ```
- Quick smoke test (mount DEE directory):
  ```bash
  docker run --rm --platform linux/amd64 \
    -v /path/to/dolby_encoding_engine:/dee \
    ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest \
    --help
  ```
- Guide: [DEE_Docker_Minimal_Wine.en.md](./DEE_Docker_Minimal_Wine.en.md)

## DME CLI Quick Entry (Container-First)

- New unified entry: `scripts/run_dme_cli.sh`
- New convenience wrappers:
  - `scripts/run_dme_ddpjoc.sh`
  - `scripts/run_dme_ddp.sh`
  - `scripts/run_dme_mux.sh`
- Mode switch: `DME_MODE=box64|fex|host` (default: `box64`)
- Optional local aliases:
  ```bash
  alias dme-joc='./scripts/run_dme_ddpjoc.sh'
  alias dme-ddp='./scripts/run_dme_ddp.sh'
  alias dme-mux='./scripts/run_dme_mux.sh'
  ```
- Examples:
  ```bash
  DME_MODE=box64 dme-joc --help
  DME_MODE=fex dme-mux --help
  DME_MODE=host dme-ddp --help
  ```
- Native `mp4muxer` override (for future self-compiled builds):
  ```bash
  MP4MUXER_NATIVE_BIN=/path/to/native/mp4muxer \
  DME_MODE=box64 dme-mux --help
  ```
  When `MP4MUXER_NATIVE_BIN` is set, `y:/...` and `z:/workspace/...` arguments are auto-converted to host paths.
- Default behavior: if `../upstream/dlb_mp4base/make/mp4muxer/macos/mp4muxer_release` exists, `dme-mux` auto-prefers the native binary.
- Disable auto-prefer: `AUTO_NATIVE_MP4MUXER=0 DME_MODE=box64 dme-mux ...`

## Documentation

- English: [DEE_Encoding_on_macOS_with_gcenx_wine.en.md](./DEE_Encoding_on_macOS_with_gcenx_wine.en.md)
- FEX container guide (English): [DEE_Docker_FEX_Experiment.en.md](./DEE_Docker_FEX_Experiment.en.md)
- Box64 container guide (English): [DEE_Docker_Box64_Experiment.en.md](./DEE_Docker_Box64_Experiment.en.md)
- Docker containerized approach (self-compiled minimal Wine, non-FEX, requires Rosetta 2): [DEE_Docker_Minimal_Wine.en.md](./DEE_Docker_Minimal_Wine.en.md)

## Included

- Markdown documentation
- Lightweight text notes

## Excluded

- Dolby binaries/packages (`.exe`, `.dll`, `.zip`)
- License files (`.lic`)
- Media test assets (`.wav`, `.ec3`)
- Runtime logs (`.log`)
- Extracted engine folders

## Open-Source License Model

1. Code and scripts: `MIT` (see [LICENSE](./LICENSE))
2. Documentation: `CC BY 4.0` (see [LICENSE-docs](./LICENSE-docs))
