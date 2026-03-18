# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

本项目提供在 Apple Silicon macOS 上运行 Windows x64 **Dolby Encoding Engine (DEE)** 和 **Dolby Media Encoder (DME) CLI** 的容器化解决方案，绕过 Rosetta 2 的限制。提供三种路线：

- **Box64**（稳定推荐）：x64 动态重编译，via `ghcr.io/sakuzypeng/dee-box64-lab:latest`
- **FEX**（实验性）：ARM64 原生模拟，via `ghcr.io/sakuzypeng/dee-fex-lab:latest`
- **Rosetta2**：自编译 Wine 9.0，via `ghcr.io/sakuzypeng/dee-wine-minimal:legacy-rosetta2-latest`

## 常用命令

### 构建镜像

```bash
# Box64 Lab（推荐，支持三种 prune profile）
./scripts/build_box64_lab.sh --profile conservative
./scripts/build_box64_lab.sh --profile medium
./scripts/build_box64_lab.sh --profile aggressive
./scripts/build_box64_lab.sh --generate-allowlist --allowlist-mode encode
./scripts/build_box64_lab.sh --build-slim

# FEX Lab
./scripts/build_fex_lab.sh

# 最小化 Wine（Rosetta2 路线）
./scripts/build_minimal_wine.sh
```

### 运行 DEE / DME CLI

```bash
# 统一 DME CLI 入口（切换 DME_MODE 环境变量）
DME_MODE=box64 ./scripts/run_dme_cli.sh --tool dee_ddpjoc_encoder.exe --help
DME_MODE=fex   ./scripts/run_dme_cli.sh --tool mp4muxer.exe --help
DME_MODE=host  ./scripts/run_dme_cli.sh --tool dee_ddp_encoder.exe --help

# 快捷脚本
./scripts/run_dme_ddpjoc.sh --help
./scripts/run_dme_ddp.sh --help
./scripts/run_mp4muxer.sh --help          # 原生 mp4muxer 快捷入口

# 直接调用执行器
IMAGE_TAG=ghcr.io/sakuzypeng/dee-box64-lab:latest ./scripts/run_dee_with_box64.sh --help
IMAGE_TAG=ghcr.io/sakuzypeng/dee-fex-lab:latest   ./scripts/run_dee_with_fex.sh --help
```

### 基准测试与验证

```bash
./scripts/benchmark_box64_baseline.sh
./scripts/benchmark_fex_native_baseline.sh
./scripts/benchmark_fex_startup_modes.sh
./scripts/acceptance_box64_candidate.sh
./scripts/run_box64_lab_probe.sh          # Box64 探针测试
./scripts/run_fex_lab_probe.sh            # FEX 探针测试
```

### FEX RootFS 准备（FEX 路线需要）

```bash
./scripts/prepare_fex_rootfs.sh
./scripts/install_wine_in_fex_rootfs_chroot.sh
./scripts/prune_fex_conservative.sh      # 或 medium / aggressive
```

## 架构

### 核心脚本

| 脚本 | 作用 |
|------|------|
| `scripts/run_dme_cli.sh` | 统一 DME CLI 入口，支持 box64/fex/host 三模式，自动路径转换，原生 mp4muxer 自动检测 |
| `scripts/run_dee_with_box64.sh` | Box64 容器执行器，挂载 ROOT_DIR 和 DEE_DIR |
| `scripts/run_dee_with_fex.sh` | FEX 容器执行器，需要预先准备的 FEX RootFS |
| `scripts/build_box64_lab.sh` | Box64 镜像构建，支持 allowlist 生成和 prune profile |

### Dockerfile

- `Dockerfile.box64-lab`：核心镜像，从源码编译 Box64，两阶段构建，多架构 APT（arm64 + amd64）
- `Dockerfile.fex-lab`：FEX 实验室镜像
- `Dockerfile.minimal-wine`：自编译 Wine 9.0，两阶段构建
- `Dockerfile`：基础最小 Wine（Rosetta2 路线）

### 运行时目录（.gitignore 排除）

- `dolby_encoding_engine/`：DEE 完整引擎（用户自行提供）
- `dme_encoder/`：DME 编码器（用户自行提供）
- `tmp_box64_state/`、`tmp_fex_rootfs/`：容器运行时状态

## 关键环境变量

```bash
DME_MODE=box64|fex|host              # DME CLI 模式选择

# host 模式 Wine 配置
HOST_WINE_BIN=wine64
HOST_WINEPREFIX=/path/to/prefix
HOST_WINEARCH=win64
HOST_WINEDEBUG=fixme-all

# 原生 mp4muxer 覆盖
MP4MUXER_NATIVE_BIN=/path/to/mp4muxer
AUTO_NATIVE_MP4MUXER=1|0

# 镜像标签覆盖
IMAGE_TAG_BOX64=dee-box64-lab:local
IMAGE_TAG_FEX=dee-fex-lab:local
```

## Commit 规范

遵循现有格式：`feat(scope):` / `fix(scope):` / `docs(scope):` / `refactor(scope):`

已验证兼容的 DEE/DME 工具：`dee_ddpjoc_encoder.exe`、`dee_ddp_encoder.exe`、`dee_convert_sample_rate.exe`、`mp4muxer.exe`、`mp4demuxer.exe`
