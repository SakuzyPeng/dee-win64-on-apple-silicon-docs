# DEE 在 macOS（Apple Silicon）上运行 Win x64 的实践笔记

本仓库用于记录并复现实验：在 Apple Silicon macOS 上通过 `gcenx/wine` 运行 Dolby Encoding Engine（Windows x64）。

补充：`FEX` 容器路线用于降低对 `Rosetta 2` 的依赖，提前应对苹果未来可能弃用 `Rosetta 2` 的风险。

English README: [README.en.md](./README.en.md)
免责声明 / Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)
许可证 / Licenses: [LICENSE](./LICENSE), [LICENSE-docs](./LICENSE-docs)

## 镜像快速入口（GHCR）

> GitHub Packages 页面会显示仓库 README；请按下列镜像入口选择对应路线。

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
