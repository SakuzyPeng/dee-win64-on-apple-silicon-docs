# DEE 在 macOS（Apple Silicon）上运行 Win x64 的实践笔记

本仓库用于记录并复现实验：在 Apple Silicon macOS 上通过 `gcenx/wine` 运行 Dolby Encoding Engine（Windows x64）。

补充：`FEX` 容器路线用于降低对 `Rosetta 2` 的依赖，提前应对苹果未来可能弃用 `Rosetta 2` 的风险。

English README: [README.en.md](./README.en.md)
免责声明 / Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)
许可证 / Licenses: [LICENSE](./LICENSE), [LICENSE-docs](./LICENSE-docs)

## 镜像快速入口（GHCR）

> GitHub Packages 页面会显示仓库 README；请按下列镜像入口选择对应路线。
> 兼容性说明（全局）：已实测兼容 Dolby Media Encoder（GUI）内置 CLI 子集（`dee_ddpjoc_encoder.exe`、`dee_ddp_encoder.exe`、`dee_convert_sample_rate.exe`、`mp4muxer.exe`、`mp4demuxer.exe`），覆盖 Box64/FEX/Rosetta2 容器与非容器 `wine64`；不代表 Dolby Media Encoder 全部工具均已验证。

### 1) FEX 路线（降低对 Rosetta 2 的依赖）

- 镜像：`ghcr.io/sakuzypeng/dee-fex-lab:latest`
- 拉取：
  ```bash
  docker pull ghcr.io/sakuzypeng/dee-fex-lab:latest
  ```
- 最短自检：
  ```bash
  IMAGE_TAG=ghcr.io/sakuzypeng/dee-fex-lab:latest ./scripts/run_dee_with_fex.sh --help
  ```
- 详细指南：[DEE_Docker_FEX_Experiment.md](./DEE_Docker_FEX_Experiment.md)

### 2) Box64 路线（并行第三路线，稳定发布）

- 镜像：`ghcr.io/sakuzypeng/dee-box64-lab:latest`
- 拉取：
  ```bash
  docker pull ghcr.io/sakuzypeng/dee-box64-lab:latest
  ```
- 最短自检：
  ```bash
  IMAGE_TAG=ghcr.io/sakuzypeng/dee-box64-lab:latest ./scripts/run_dee_with_box64.sh --help
  ```
- 详细指南：[DEE_Docker_Box64_Experiment.md](./DEE_Docker_Box64_Experiment.md)
- 可回退标签：`full-latest`、`slim-latest`（`latest` 始终指向最近一次完整验收通过版本）

### 3) Rosetta 2 路线（非 FEX，兼容方案）

- 镜像：`ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest`
- 拉取：
  ```bash
  docker pull ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest
  ```
- 最短自检（需挂载 DEE 目录）：
  ```bash
  docker run --rm --platform linux/amd64 \
    -v /path/to/dolby_encoding_engine:/dee \
    ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest \
    --help
  ```
- 详细指南：[DEE_Docker_Minimal_Wine.md](./DEE_Docker_Minimal_Wine.md)

## DME CLI 快捷入口（容器优先）

- 新增统一入口：`scripts/run_dme_cli.sh`
- 新增快捷脚本：
  - `scripts/run_dme_ddpjoc.sh`
  - `scripts/run_dme_ddp.sh`
  - `scripts/run_mp4muxer.sh`
- 模式切换：`DME_MODE=box64|fex|host`（默认 `box64`）
- 可选 alias（本机）：
  ```bash
  alias dme-joc='./scripts/run_dme_ddpjoc.sh'
  alias dme-ddp='./scripts/run_dme_ddp.sh'
  alias mp4muxer='./scripts/run_mp4muxer.sh'
  ```
- 示例：
  ```bash
  DME_MODE=box64 dme-joc --help
  DME_MODE=fex mp4muxer --help
  DME_MODE=host dme-ddp --help
  ```
- `mp4muxer` 原生替换（便于后续自编译版本）：
  ```bash
  MP4MUXER_NATIVE_BIN=/path/to/native/mp4muxer \
  DME_MODE=box64 mp4muxer --help
  ```
  `MP4MUXER_NATIVE_BIN` 启用时，会自动把 `y:/...` 或 `z:/workspace/...` 参数转换为宿主机路径。
- 默认行为：若存在 `../upstream/dlb_mp4base/make/mp4muxer/macos/mp4muxer_release`，`mp4muxer` 会自动优先使用原生二进制。
- 关闭自动优先：`AUTO_NATIVE_MP4MUXER=0 DME_MODE=box64 mp4muxer ...`

## 文档入口

- 中文（主文档）：[DEE_Encoding_on_macOS_with_gcenx_wine.md](./DEE_Encoding_on_macOS_with_gcenx_wine.md)
- FEX 容器指南（中文）：[DEE_Docker_FEX_Experiment.md](./DEE_Docker_FEX_Experiment.md)
- Box64 容器指南（中文）：[DEE_Docker_Box64_Experiment.md](./DEE_Docker_Box64_Experiment.md)
- 容器化方案（Docker + 自编译精简 Wine，非 FEX，依赖 Rosetta 2）：[DEE_Docker_Minimal_Wine.md](./DEE_Docker_Minimal_Wine.md)

## 仓库包含内容

- Markdown 文档
- 轻量文本说明

## 仓库不包含内容

- Dolby 工具二进制/安装包（`.exe`、`.dll`、`.zip`）
- 授权文件（`.lic`）
- 媒体测试资产（`.wav`、`.ec3`）
- 运行日志（`.log`）
- 解压后的引擎目录

## 开源许可证说明

1. 代码与脚本：`MIT`（见 [LICENSE](./LICENSE)）
2. 文档内容：`CC BY 4.0`（见 [LICENSE-docs](./LICENSE-docs)）
