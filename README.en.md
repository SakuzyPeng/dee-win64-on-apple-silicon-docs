# DEE on macOS (Apple Silicon): Running Win x64 Workflow Notes

This repository documents and reproduces a practical setup for running Dolby Encoding Engine (Windows x64) on Apple Silicon macOS via `gcenx/wine`.

Note: the `FEX` container track is used to reduce dependency on `Rosetta 2` and prepare for a potential future deprecation of `Rosetta 2` by Apple.

## Read Me in Chinese

- 中文 README: [README.md](./README.md)
- Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)
- Licenses: [LICENSE](./LICENSE), [LICENSE-docs](./LICENSE-docs)

## Container Quick Start (GHCR)

> GitHub Packages renders the repository README; use the image-specific entry points below.

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
- Compatibility note: also validated with Dolby Media Encoder (GUI) built-in CLI tools (for example `dee_ddpjoc_encoder.exe` and `mp4muxer.exe`); this repository does not distribute Dolby binaries/license payloads.
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
