# DEE on macOS (Apple Silicon): Running Win x64 Workflow Notes

This repository documents and reproduces a practical setup for running Dolby Encoding Engine (Windows x64) on Apple Silicon macOS via `gcenx/wine`.

## Read Me in Chinese

- 中文 README: [README.md](./README.md)
- Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)
- Licenses: [LICENSE](./LICENSE), [LICENSE-docs](./LICENSE-docs)

## Documentation

- Chinese (primary): [DEE_Encoding_on_macOS_with_gcenx_wine.md](./DEE_Encoding_on_macOS_with_gcenx_wine.md)
- English: [DEE_Encoding_on_macOS_with_gcenx_wine.en.md](./DEE_Encoding_on_macOS_with_gcenx_wine.en.md)

## Included

- Markdown documentation
- Lightweight text notes

## Excluded

- Dolby binaries/packages (`.exe`, `.dll`, `.zip`)
- License files (`.lic`)
- Media test assets (`.wav`, `.ec3`)
- Runtime logs (`.log`)
- Extracted engine folders

## Before making this repository public

1. Verify `git ls-files` includes docs/text only (no binaries, licenses, or media assets).
2. Verify commit history contains no accidental sensitive data (tokens, private keys, local absolute paths, etc.).
3. Review and accept the boundaries in [DISCLAIMER.md](./DISCLAIMER.md).
4. Confirm license split is aligned with your sharing intent (code/scripts vs docs).

## Open-Source License Model

1. Code and scripts: `MIT` (see [LICENSE](./LICENSE))
2. Documentation: `CC BY 4.0` (see [LICENSE-docs](./LICENSE-docs))
