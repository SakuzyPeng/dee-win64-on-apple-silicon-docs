# DEE Box64 容器使用指南（ARM64）

## 适用范围
- 目标：在 Apple Silicon 上以 `box64 + wine64:amd64` 运行 `dee.exe`。
- 定位：作为 FEX / Rosetta2 之外的并行第三路线。
- 优先级：先保证 `ADM -> EC3` 稳定，再做性能优化。
- 裁剪边界：只裁剪容器运行时，不裁剪 DEE 本体。

## 前置条件
- 已安装 Docker（支持 `linux/arm64`）。
- 仓库根目录存在：
  - `dolby_encoding_engine/dee.exe`
  - `dolby_encoding_engine/license.lic`
  - `testADM.wav`

## 快速开始（full 镜像）
1. 构建：
```bash
./scripts/build_box64_lab.sh --profile aggressive
```
2. 探针：
```bash
IMAGE_TAG=dee-box64-lab:local ./scripts/run_box64_lab_probe.sh
```
3. 冒烟：
```bash
IMAGE_TAG=dee-box64-lab:local ./scripts/run_dee_with_box64.sh --help
IMAGE_TAG=dee-box64-lab:local ./scripts/run_dee_with_box64.sh --print-stages
```
4. 真编码（ADM -> EC3）：
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

## 激进裁剪（slim 镜像）
1. 生成运行时白名单（建议 `encode` 模式）：
```bash
./scripts/generate_box64_runtime_allowlist.sh \
  --image dee-box64-lab:local \
  --mode encode \
  --out-dir tmp_box64_prune/allowlist
```
2. 生成 slim：
```bash
./scripts/build_box64_allowlist_slim.sh \
  --source-image dee-box64-lab:local \
  --target-image dee-box64-lab:slim-local \
  --allowlist tmp_box64_prune/allowlist/runtime-allowlist.txt
```
3. slim 冒烟与真编码：把上面命令的 `IMAGE_TAG` 改为 `dee-box64-lab:slim-local`。

稳定性护栏：
- slim 默认保留完整 Wine 运行时目录：
  - `/usr/lib/wine`
  - `/usr/lib/x86_64-linux-gnu/wine`
  - `/usr/share/wine`
- 其余部分按 allowlist 裁剪，避免关键 DLL/EXE 漏拷导致回归。

一条命令串联（aggressive + allowlist + slim）：
```bash
./scripts/build_box64_lab.sh \
  --profile aggressive \
  --generate-allowlist \
  --allowlist-mode encode \
  --build-slim \
  --slim-tag dee-box64-lab:slim-local
```

## 验收清单
- 冒烟：`--help`、`--print-stages` 返回 `0`。
- 真编码：`ADM WAV -> Atmos DDP EC3` 成功，输出文件和日志存在。
- 稳定性：同命令连续 5 次 `5/5` 成功。
```bash
IMAGE_TAG=dee-box64-lab:slim-local ./scripts/acceptance_box64_candidate.sh
```
- 基线（与既有格式兼容）：
```bash
IMAGE_TAG=dee-box64-lab:slim-local ./scripts/benchmark_box64_baseline.sh
```
- 体积报告：
```bash
./scripts/report_box64_image_size.sh --image dee-box64-lab:slim-local
```

## 体积基线（2026-03-08）
基线快照（本地构建）：

| 镜像 | 大小（docker image inspect） | 备注 |
|---|---:|---|
| `dee-box64-lab:local` | `996,322,519` bytes（约 `950.17 MiB`） | full |
| `dee-box64-lab:slim-local` | `773,213,959` bytes（约 `737.39 MiB`） | slim |

体积门槛：
- 发布门槛：`<= 850MB`
- 冲刺目标：约 `700MB`（非首轮阻塞）

复测命令：
```bash
./scripts/report_box64_image_size.sh --image dee-box64-lab:local --out-dir tmp_box64_prune/size-full
./scripts/report_box64_image_size.sh --image dee-box64-lab:slim-local --out-dir tmp_box64_prune/size-slim
```

基线更新规则：
- 每次改动裁剪策略后更新一次体积基线。
- 发布前保留一份最终 `size-report.tsv` 作为发布记录。

## 发布与回退
镜像：`ghcr.io/sakuzypeng/dee-box64-lab`

建议标签：
- `vYYYY.MM.DD`
- `full-latest`
- `slim-latest`
- `latest`（当前稳定发布入口）

规则：
- `latest` 仅指向通过完整验收的版本。
- 若 slim 未通过，仅更新 `full-latest` 并附阻塞说明，`latest` 保持不变。
- 始终保留 full/slim 双入口，确保可回退。

## 常见问题
1. `nodrv_CreateWindow` 在无头环境通常是噪声日志，不等于失败。
2. DEE 要求 `--temp` 目录存在；封装脚本会自动创建 `y:/...` 对应宿主目录。
3. 磁盘紧张时优先清理：`tmp_box64_state*`、`tmp_box64_prune/`、`tmp_bench/`。
