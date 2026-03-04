# Dolby Encoding Engine 在 macOS 上使用 gcenx/wine（实测笔记）

## 1. 目标

在 Apple Silicon macOS 上稳定运行 `dolby_encoding_engine`，并完成实际编码任务（`ADM WAV -> EC3`）。

---

## 2. 最终结论

`gcenx/wine` 可稳定运行本项目中的 `dee.exe`：

1. `dee.exe --help` 正常。
2. `dee.exe --print-stages -l license.lic` 正常加载插件与授权。
3. 使用模板实际编码 `testADM.wav -> testADM_out.ec3` 成功，进度 100%。

---

## 3. 本次环境

1. 硬件：Apple Silicon Mac
2. 系统：macOS
3. Homebrew：已安装
4. Wine 实现：`wine-crossover`（tap: `gcenx/wine`）
5. Wine 版本：`wine-8.0.1 (CrossOverFOSS 23.7.1)`

---

## 4. 一次性安装步骤

### 4.1 安装 gcenx/wine

```bash
brew tap gcenx/wine
brew install --cask wine-crossover
```

确认版本：

```bash
wine --version
wine64 --version
```

### 4.2 初始化独立前缀（建议）

```bash
export WINEPREFIX="$HOME/.wine-dee-gcenx"
export WINEDEBUG=fixme-all
wineboot -u
```

### 4.3 安装 VC++ 运行库（关键）

`dolby_encoding_engine` 依赖 `VCRUNTIME140/MSVCP140/UCRT`，必须安装：

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

## 5. 项目内验证命令

```bash
export WINEPREFIX="$HOME/.wine-dee-gcenx"
export WINEDEBUG=fixme-all
cd /path/to/dee-win/dolby_encoding_engine

wine64 dee.exe --help
wine64 dee.exe --print-stages -l license.lic
```

---

## 6. 实际编码测试（ADM WAV -> EC3）

使用测试模板：

`/path/to/dee-win/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml`

执行：

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

输出文件：

`/path/to/dee-win/testADM_out.ec3`

日志：

`/path/to/dee-win/dee_test_atmos_gcenx.log`

---

## 7. 全局命令（任意目录直接用 dee）

已配置包装脚本：

`~/bin/dee`

用法：

```bash
dee --help
dee --print-stages
dee --xml /path/to/job.xml --progress --stdout
```

脚本默认行为：

1. 使用 `WINEPREFIX=$HOME/.wine-dee-gcenx`
2. 调用 `$DEE_HOME/dee.exe`
3. 未显式传 `-l/--license-file` 时自动补 `license.lic`

---

## 8. 常见问题与处理

1. `wine64: command not found`
   - 先执行：`brew install --cask wine-crossover`

2. 报缺少 `VCRUNTIME140.dll` / `MSVCP140.dll`
   - 重新执行第 4.3 节的 VC++ 运行库安装。

3. XML 模板直接运行失败
   - 官方模板常含占位符（如 `FILE_NAME_A`、`PATH`），必须替换为真实路径。

4. 想隔离不同项目
   - 为每个项目单独设 `WINEPREFIX`，避免依赖冲突。

5. 路径与转义字符问题（推荐）
   - XML 中优先使用正斜杠路径：`Z:/path/to/...`，避免 `\\` 转义错误。
   - 若在 shell 命令里传含空格路径，务必使用引号：`\"/path/with space/file.xml\"`。

---

## 9. 建议

1. 生产任务建议固定使用 `gcenx/wine`，保持运行环境一致性。
2. 保留独立前缀 `~/.wine-dee-gcenx`，只用于 DEE。
3. 将模板与日志固化到项目中，便于团队复现。

---

## 10. 附录：包装脚本模板

> 建议将脚本保存为 `~/bin/dee` 并 `chmod +x ~/bin/dee`。

```bash
#!/usr/bin/env bash
set -euo pipefail

# 按需改成你的实际目录
DEE_HOME="${DEE_HOME:-/path/to/dee-win/dolby_encoding_engine}"
DEE_EXE="${DEE_EXE:-$DEE_HOME/dee.exe}"
DEE_LICENSE="${DEE_LICENSE:-$DEE_HOME/license.lic}"

# 独立 Wine 前缀，避免污染默认 ~/.wine
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
