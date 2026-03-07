# DEE on macOS (Apple Silicon): Running Win x64 Workflow Notes

This repository documents and reproduces a practical setup for running Dolby Encoding Engine (Windows x64) on Apple Silicon macOS via `gcenx/wine`.

Note: the `FEX` container track is used to reduce dependency on `Rosetta 2` and prepare for a potential future deprecation of `Rosetta 2` by Apple.

## Read Me in Chinese

- 中文 README: [README.md](./README.md)
- Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)
- Licenses: [LICENSE](./LICENSE), [LICENSE-docs](./LICENSE-docs)

## Documentation

- Chinese (primary): [DEE_Encoding_on_macOS_with_gcenx_wine.md](./DEE_Encoding_on_macOS_with_gcenx_wine.md)
- English: [DEE_Encoding_on_macOS_with_gcenx_wine.en.md](./DEE_Encoding_on_macOS_with_gcenx_wine.en.md)
- FEX container guide (Chinese): [DEE_Docker_FEX_Experiment.md](./DEE_Docker_FEX_Experiment.md)
- FEX container guide (English): [DEE_Docker_FEX_Experiment.en.md](./DEE_Docker_FEX_Experiment.en.md)
- Docker containerized approach (self-compiled minimal Wine): [DEE_Docker_Minimal_Wine.en.md](./DEE_Docker_Minimal_Wine.en.md)

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
