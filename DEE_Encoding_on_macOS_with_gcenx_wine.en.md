# Dolby Encoding Engine on macOS with gcenx/wine (Practical Notes)

## 1. Goal

Run `dolby_encoding_engine` reliably on Apple Silicon macOS, and complete a real encoding workflow (`ADM WAV -> EC3`).

---

## 2. Final Result

`gcenx/wine` works reliably for `dee.exe` in this workflow:

1. `dee.exe --help` runs successfully.
2. `dee.exe --print-stages -l license.lic` loads plugins and license correctly.
3. A real template-based encode (`testADM.wav -> testADM_out.ec3`) completes with 100% progress.

---

## 3. Environment

1. Hardware: Apple Silicon Mac
2. OS: macOS
3. Package manager: Homebrew
4. Wine implementation: `wine-crossover` (tap: `gcenx/wine`)
5. Wine version used in testing: `wine-8.0.1 (CrossOverFOSS 23.7.1)`

---

## 4. One-Time Setup

### 4.1 Install gcenx/wine

```bash
brew tap gcenx/wine
brew install --cask wine-crossover
```

Check installation:

```bash
wine --version
wine64 --version
```

### 4.2 Initialize an Isolated Prefix (Recommended)

```bash
export WINEPREFIX="$HOME/.wine-dee-gcenx"
export WINEDEBUG=fixme-all
wineboot -u
```

### 4.3 Install VC++ Runtime (Required)

`dolby_encoding_engine` depends on `VCRUNTIME140/MSVCP140/UCRT`.

```bash
mkdir -p /tmp/vcredist-gcenx
cd /tmp/vcredist-gcenx
curl -fL https://aka.ms/vs/17/release/vc_redist.x64.exe -o vc_redist.x64.exe
curl -fL https://aka.ms/vs/17/release/vc_redist.x86.exe -o vc_redist.x86.exe

export WINEPREFIX="$HOME/.wine-dee-gcenx"
export WINEDEBUG=fixme-all
wine64 vc_redist.x64.exe /install /quiet /norestart
wine64 vc_redist.x86.exe /install /quiet /norestart
```

---

## 5. In-Project Verification Commands

```bash
export WINEPREFIX="$HOME/.wine-dee-gcenx"
export WINEDEBUG=fixme-all
cd /path/to/dee-win/dolby_encoding_engine

wine64 dee.exe --help
wine64 dee.exe --print-stages -l license.lic
```

---

## 6. Real Encoding Test (ADM WAV -> EC3)

Template used:

`/path/to/dee-win/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml`

Run:

```bash
export WINEPREFIX="$HOME/.wine-dee-gcenx"
export WINEDEBUG=fixme-all
cd /path/to/dee-win/dolby_encoding_engine

wine64 dee.exe \
  --xml /path/to/dee-win/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml \
  -l /path/to/dee-win/dolby_encoding_engine/license.lic \
  --log-file /path/to/dee-win/dee_test_atmos_gcenx.log \
  --stdout \
  --progress
```

Output file:

`/path/to/dee-win/testADM_out.ec3`

Log file:

`/path/to/dee-win/dee_test_atmos_gcenx.log`

---

## 7. Global `dee` Command (Run from Any Directory)

Configured wrapper location:

`~/bin/dee`

Usage:

```bash
dee --help
dee --print-stages
dee --xml /path/to/job.xml --progress --stdout
```

Default wrapper behavior:

1. Uses `WINEPREFIX=$HOME/.wine-dee-gcenx`
2. Runs `$DEE_HOME/dee.exe`
3. Auto-adds `license.lic` if `-l/--license-file` is not provided

---

## 8. Troubleshooting

1. `wine64: command not found`
   - Run: `brew install --cask wine-crossover`

2. Missing `VCRUNTIME140.dll` / `MSVCP140.dll`
   - Re-run the VC++ runtime installation in section 4.3.

3. Template fails immediately
   - Official XML templates often contain placeholders (for example `FILE_NAME_A`, `PATH`). Replace them with real values first.

4. Need project isolation
   - Use a dedicated `WINEPREFIX` per project to avoid dependency conflicts.

5. Path and escaping issues (recommended practice)
   - Use forward slashes in XML paths: `Z:/path/to/...` to avoid `\\` escaping mistakes.
   - Quote paths with spaces in shell commands: `\"/path/with space/file.xml\"`.

---

## 9. Recommendations

1. For production, keep `gcenx/wine` as a fixed runtime to maintain environment consistency.
2. Keep a dedicated prefix such as `~/.wine-dee-gcenx` for DEE only.
3. Store templates and logs in a reproducible structure for team handoff.

---

## 10. Appendix: Wrapper Script Template

> Save as `~/bin/dee` and run `chmod +x ~/bin/dee`.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Adjust to your local paths
DEE_HOME="${DEE_HOME:-/path/to/dee-win/dolby_encoding_engine}"
DEE_EXE="${DEE_EXE:-$DEE_HOME/dee.exe}"
DEE_LICENSE="${DEE_LICENSE:-$DEE_HOME/license.lic}"

# Dedicated Wine prefix (avoid polluting default ~/.wine)
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-dee-gcenx}"
export WINEPREFIX
export WINEDEBUG="${WINEDEBUG:-fixme-all}"

if ! command -v wine64 >/dev/null 2>&1; then
  echo "Error: wine64 not found. Install gcenx/wine first." >&2
  exit 1
fi

if [ ! -f "$DEE_EXE" ]; then
  echo "Error: dee.exe not found: $DEE_EXE" >&2
  exit 1
fi

args=("$@")
need_license=1
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    -l|--license-file|--license-mem)
      need_license=0
      break
      ;;
  esac
done

if [ "$need_license" -eq 1 ] && [ -f "$DEE_LICENSE" ]; then
  args+=("-l" "$DEE_LICENSE")
fi

exec wine64 "$DEE_EXE" "${args[@]}"
```
