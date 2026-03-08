# DEE Box64 容器运行指南（ARM64）

## 目标
在 Apple Silicon 上新增 `box64` 并行容器路线，运行 DEE CLI 编码任务，并作为可发布候选方案维护。

采用 `box64` 的定位：
- 与 `FEX`、`Rosetta 2` 并行，不替代现有路线
- 先保证功能稳定与可迁移，再讨论性能优化

## 路线定义
### 路径 A（首选目标）
- `linux/arm64` 基础镜像
- `box64 + wine64:amd64`（multiarch）
- 直接运行 `dee.exe`

### 路径 B（回退预案）
- 若路径 A 在一个迭代窗口内无法通过 `ADM -> EC3` 验收
- 切换到 `amd64` 用户态 RootFS + box64
- 不影响现有 FEX/Rosetta2 路线与发布

> 当前仓库实现为路径 A：在 `linux/arm64` 容器中自编译新版 `box64`，并使用 multiarch 的 `wine64:amd64` 直接运行 `dee.exe`。

## 路径 A 修复记录（历史阻塞 -> 当前可用）
- 时间：2026-03-08
- 路径 A 观测到的阻塞现象：
  - `wine: could not load kernel32.dll, status c0000135`
  - 无头环境出现大量 `nodrv_CreateWindow` / `explorer.exe /desktop` 异常噪声
  - `--help/--print-stages` 在并发或冷启动条件下稳定性不足
- 处理：将容器内 `box64` 从旧版仓库包升级为新版源码构建版本后，路径 A 恢复通过 `--help/--print-stages/ADM->EC3/5x稳定性` 验收。
- 结论：路径 B 继续保留为应急回退，但默认发布目标回到路径 A。

## 关键脚本
- `scripts/build_box64_lab.sh`
- `scripts/run_box64_lab_probe.sh`
- `scripts/run_dee_with_box64.sh`
- `scripts/benchmark_box64_baseline.sh`
- `scripts/acceptance_box64_candidate.sh`

## 一次性初始化
1. 构建实验镜像
```bash
./scripts/build_box64_lab.sh
```

2. 探测 box64/wine 运行基础
```bash
./scripts/run_box64_lab_probe.sh
```

## 日常运行
CLI 冒烟：
```bash
./scripts/run_dee_with_box64.sh --help
```

`print-stages`：
```bash
./scripts/run_dee_with_box64.sh \
  --print-stages \
  -l y:/dolby_encoding_engine/license.lic
```

ADM 示例编码：
```bash
./scripts/run_dee_with_box64.sh \
  --xml y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml \
  --input-audio y:/testADM.wav \
  --output y:/tmp_box64_acceptance/manual/testADM.ec3 \
  --temp y:/tmp_box64_acceptance/manual/tmp \
  --log-file y:/tmp_box64_acceptance/manual/dee.log \
  -l y:/dolby_encoding_engine/license.lic \
  --stdout \
  --verbose info
```

## 运行约定
`run_dee_with_box64.sh` 已内置：
- `WINEPREFIX` 初始化
- 盘符映射
- `c:` -> `../drive_c`
- `z:` -> `/`
- `y:` -> `/workspace`
- 首次自动 `wineboot -u`
- 对 `y:/...` 的 `--temp/--log-file/--output` 自动创建宿主机目录

默认状态目录：
- `tmp_box64_state/`（可删除后重建）

## 验收标准（发布门槛）
1. 冒烟：
```bash
./scripts/run_dee_with_box64.sh --help
./scripts/run_dee_with_box64.sh --print-stages -l y:/dolby_encoding_engine/license.lic
```

2. 真实编码：`ADM -> EC3` 成功，输出文件与日志存在，退出码 `0`

3. 稳定性：同一编码命令连续 5 次成功
```bash
./scripts/acceptance_box64_candidate.sh
```

4. 基线记录（本阶段不设性能门槛）：
```bash
./scripts/benchmark_box64_baseline.sh
```

## GHCR 发布策略
镜像命名：
- `ghcr.io/sakuzypeng/dee-box64-lab`

标签策略：
- 候选：`candidate-YYYYMMDD-HHMMSS`
- 日期：`vYYYY.MM.DD`
- 稳定：`latest`（仅在完整验收通过后更新）

示例：
```bash
docker tag dee-box64-lab:local ghcr.io/sakuzypeng/dee-box64-lab:candidate-$(date +%Y%m%d-%H%M%S)
docker tag dee-box64-lab:local ghcr.io/sakuzypeng/dee-box64-lab:v$(date +%Y.%m.%d)
docker push ghcr.io/sakuzypeng/dee-box64-lab:candidate-$(date +%Y%m%d-%H%M%S)
docker push ghcr.io/sakuzypeng/dee-box64-lab:v$(date +%Y.%m.%d)
# latest 仅在验收通过后手动提升
```

## 常见问题
1. 当前镜像在容器内自编译新版 `box64`，并使用 multiarch 安装 `wine64:amd64`。
2. 无 GUI 场景出现 `nodrv_CreateWindow` 类日志通常可忽略。
3. DEE 要求 `--temp` 目录存在；脚本已自动创建 `y:/...` 对应宿主目录。
4. 如遇空间不足，优先清理 `tmp_box64_state*` 与历史基准目录。
