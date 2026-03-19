# DEE FEX Bundled 诊断与回归（已跑通）

## 1. 目标

在 Apple Silicon 上验证 `DEE_FEX_Bundled` 单镜像方案：

- RootFS 内嵌到镜像（不依赖外部挂载 RootFS）
- `dee.exe --help` 可正常运行
- 真实编码 `ADM -> Atmos DDP EC3` 可完成

## 2. 最新状态（2026-03-17）

结论：**已跑通**，此前的 `exit 127` 问题已修复。

关键回归结果：

1. 镜像构建成功  
   - `IMAGE_TAG=dee-fex-bundled:test ./scripts/build_fex_bundled.sh`
   - 构建耗时：`4m15.565s`
   - 镜像大小：`dee-fex-bundled:test 1.44GB`

2. `--help` 回归成功  
   - `IMAGE_TAG=dee-fex-bundled:test ./scripts/run_dee_with_fex_bundled.sh --help`
   - 退出码：`0`
   - 可正常输出 `dee.exe` 帮助信息
   - 冷启动验证（全新 `STATE_DIR`）同样 `exit=0`

3. 真实编码回归成功（ADM -> Atmos DDP EC3）  
   - 命令：
     ```bash
     IMAGE_TAG=dee-fex-bundled:test ./scripts/run_dee_with_fex_bundled.sh \
       --xml y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml \
       --input-audio y:/testADM.wav \
       --output y:/tmp_fex_bundled_state/testADM_fex_bundled.ec3 \
       --temp y:/tmp_fex_bundled_state/tmp \
       --log-file y:/tmp_fex_bundled_state/testADM_fex_bundled.log \
       --stdout --verbose info
     ```
   - 退出码：`0`
   - 日志关键结果：`Overall progress: 100.0`
   - 冷启动 `STATE_DIR` 再跑一轮仍为 `exit=0`，`Job execution took 10 seconds`
   - 产物：
     - `tmp_fex_bundled_state/testADM_fex_bundled.ec3`（2.7MB）
     - `tmp_fex_bundled_state/testADM_fex_bundled.log`（7.5KB）
     - `tmp_fex_bundled_state_cold/testADM_fex_bundled_cold.ec3`（2.7MB）
     - `tmp_fex_bundled_state_cold/testADM_fex_bundled_cold.log`（7.5KB）

## 3. 根因定位（旧问题）

旧问题表现：`wineboot` / `dee.exe --help` 在 bundled 镜像内直接 `exit 127`，几乎无有效输出。

核心根因：

- `wineserver` 是 `#!/bin/sh -e` 脚本。
- Bundled RootFS 中缺少可用的 `/bin/sh`（在 merged-usr 布局下本质要有 `usr/bin/sh` 可解析）。
- 结果是 shebang 解释器找不到，触发 `127`。

## 4. 修复内容

文件：`Dockerfile.fex-bundled`

在 RootFS 符号链接构建阶段补充：

```dockerfile
ln -s bash ${ROOTFS_PATH}/usr/bin/sh
```

同时保留 HOST 层 `wine*` 二进制（供 FEX 的 `exec()` 拦截路径解析）。

文件：`scripts/run_dee_with_fex_bundled.sh`

- 修正首次初始化逻辑：仅当 `wineboot` 成功时才写入 `.dee_fex_bundled_ready`
- 若 `wineboot` 失败则直接退出，避免“假初始化成功”掩盖问题

## 5. 现阶段结论

`DEE_FEX_Bundled` 当前已经满足“可构建、可运行、可真实编码”的实验目标，可以进入下一阶段（性能基线与进一步裁剪）。

## 6. 裁剪计划实施（2026-03-17）

已按“三阶段 + 闸门”方案落地接口，并完成 Phase 1 验收：

1. 新增构建参数  
   - `BUNDLED_TRIM_LEVEL=safe|balanced|aggressive`（默认 `safe`）  
   - 入口：`scripts/build_fex_bundled.sh`

2. 新增基线冻结文件  
   - `configs/fex_bundled_baseline.env`（体积/性能基线与阈值）  
   - `scripts/benchmark_fex_bundled_gate.sh` 默认读取

3. 新增离线白名单产物  
   - `configs/fex_bundled_allowlist.txt`（wine builtins）  
   - `configs/fex_bundled_aggressive_allowlist.txt`（非 wine `.so`）

4. 新增离线采集脚本  
   - `scripts/capture_fex_bundled_allowlist.sh`  
   - 采集口径：`strace -f -e trace=file`，覆盖 `help_cold + encode`

5. 新增闸门基准脚本  
   - `scripts/benchmark_fex_bundled_gate.sh`  
   - 功能闸门：`help cold/warm` + `encode x3` + 输出非空 + `Overall progress: 100.0`  
   - 性能闸门：默认基线 `18.450s`，阈值 `19.373s`（+5%）

Phase 1（`safe`）实测结果：

- 构建命令：  
  `IMAGE_TAG=dee-fex-bundled:phase1-safe BUNDLED_TRIM_LEVEL=safe ./scripts/build_fex_bundled.sh`
- 构建耗时：`2m46.409s`
- 闸门命令：  
  `IMAGE_TAG=dee-fex-bundled:phase1-safe RUNS=3 ./scripts/benchmark_fex_bundled_gate.sh`
- 结果：
  - `encode mean real = 18.280s`（通过性能闸门）
  - 镜像体积 `0.858 GiB`（已达到 `~1.0GB` 目标）

结论：已在低风险阶段达到体积目标，按计划可停止继续激进裁剪。

补充（同日后续探索）：

- `balanced` 经过白名单补全后已通过闸门回归：  
  `IMAGE_TAG=dee-fex-bundled:phase2-balanced RUNS=3 ./scripts/benchmark_fex_bundled_gate.sh`
- 结果：
  - `encode mean real = 17.993s`（通过性能闸门）
  - 镜像体积仍为 `0.858 GiB`（与 `safe` 基本一致）

因此目前建议：

- 稳定默认：`safe`
- 可选实验：`balanced`（已可用，但当前体积收益不明显）

## 7. Balanced 深化裁剪更新（2026-03-17 晚）

后续已完成两项关键修正：

1. 修复“假裁剪”  
   - 之前 `balanced` 体积不降的核心原因是“先 `COPY` 全量，再 `rm`”，删除发生在后层。  
   - 现已改为在 `rootfs_payload_builder` 阶段先裁剪，再拷贝到 final 层。  
   - 结果：`phase2-balanced` 实际下降到约 `347MB`（`safe` 约 `921MB`）。

2. 补充 `balanced` 可移除项验证  
   - 新增脚本：`scripts/probe_fex_bundled_balanced_removals.sh`  
   - 方法：对候选文件逐项“单删 -> gate（help cold/warm + encode）”。
   - 结论：
     - `start.exe` 不能删：删除后 `wineboot initialization failed`，功能闸门失败。
     - `winex11.drv` 可删（单删闸门通过）。
     - `msacm.* / sane.ds / winemac.drv` 在当前镜像中已不存在（allowlist 冗余项）。

已据此回写 `configs/fex_bundled_allowlist.txt`（保留 `start.exe`，清理冗余项），并完成复测：

- 构建：  
  `IMAGE_TAG=dee-fex-bundled:phase2-balanced-v2 BUNDLED_TRIM_LEVEL=balanced ./scripts/build_fex_bundled.sh`  
  构建耗时：`1m59.962s`
- 闸门：  
  `IMAGE_TAG=dee-fex-bundled:phase2-balanced-v2 RUNS=3 ./scripts/benchmark_fex_bundled_gate.sh`
- 结果：  
  - `encode mean real = 16.860s`（阈值 `19.373s`，通过）  
  - 功能闸门：`PASS`  
  - 镜像体积：`346MB`（约 `0.323 GiB`）

以上结论对应 `phase2-balanced-v2` 时点（历史里程碑）。

## 8. v3/v4 回归与收敛（2026-03-18 ~ 2026-03-19）

后续在“严格冷启动优先”的口径下继续推进：

1. v3 阶段暴露冷启动回归（远端机更容易复现）  
   - 典型日志：`load_apiset_dll failed ... c000000f`、`failed to open ... syswow64\\rundll32.exe: c0000135`。  
   - 现象：部分场景 `--help` 可能看似可用，但严格冷启动 gate 失败。

2. 根因与修复  
   - 根因：`balanced` allowlist 过度裁剪，误伤了冷启动关键 builtin/依赖。  
   - 修复：回补关键 wine builtins 与启动路径（提交：`2b8e545`，`fix(fex-bundled): restore critical wine builtins for balanced trim`）。  
   - 随后将默认入口统一切到 `v4`（提交：`3e0c213`，`docs/scripts: switch fex-bundled defaults to phase2-balanced-v4`）。

3. v4 验证结果（当前稳定口径）  
   - 严格冷启动检查：以全新 `WINEPREFIX` 运行，`exit=0`。  
   - 远端真实编码（`ADM -> AC4`）通过：  
     - `ENCODE_RC=0`  
     - `Overall progress: 100.0`  
     - `Job execution took 473 seconds (0h7m53s)`  
     - 输出：`ADM_ac4_default.ac4`（约 `6.0MB`）  
     - 监控峰值：`Max MEM usage in system: 984 MB`

4. 包与标签收敛  
   - `phase2-balanced-v3` 已从 GHCR 删除。  
   - 在 `v5` 发布前仅保留并维护：`phase2-balanced-v4` + 稳定别名 `phase2-balanced`（指向 `v4`）。

## 9. 当前默认与建议

当前脚本默认已切到 `v5`：

- `scripts/build_fex_bundled.sh`：默认 `BUNDLED_TRIM_LEVEL=balanced`，默认 `IMAGE_TAG=dee-fex-bundled:phase2-balanced-v5`
- `scripts/run_dee_with_fex_bundled.sh`：默认镜像 `dee-fex-bundled:phase2-balanced-v5`
- `scripts/benchmark_fex_bundled_gate.sh`：默认镜像 `dee-fex-bundled:phase2-balanced-v5`
- `scripts/check_fex_bundled_cold_start.sh`：默认镜像 `dee-fex-bundled:phase2-balanced-v5`
- 稳定别名：`dee-fex-bundled:phase2-balanced -> phase2-balanced-v5`

建议流程：

1. 每次变更先跑严格冷启动 gate（全新 `STATE_DIR/WINEPREFIX`）。  
2. 再跑真实编码（至少一条 `ADM -> Atmos/AC4`）。  
3. 通过后再更新默认标签或文档口径。

## 10. v5 发布记录（2026-03-19）

1. 问题归因与最小回补  
   - 现象：`phase2-balanced-v4` 在 `dee.exe --json ...` direct MP4 输出阶段崩溃，典型为 `Unhandled exception code c0000409`。  
   - 对照：`safe-trim` 路线可通过 direct MP4，但镜像约 `921MB`，不满足体积目标。  
   - 结论：最小必要回补集合收敛到 `cmd.exe`（`/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/cmd.exe`）。

2. 工程化修复  
   - `capture_fex_bundled_allowlist.sh` 新增 `mp4_direct` 采集模式，并补齐 `WinePrefix/system32 -> builtin` 映射。  
   - `configs/fex_bundled_allowlist.txt` 与 `Dockerfile.fex-bundled` 的 `balanced` keep 集均加入 `cmd.exe`。  
   - `benchmark_fex_bundled_gate.sh` 纳入 direct MP4 功能检查与 `ffprobe`（AC4）验收。

3. 发布与体积  
   - 发布标签：`ghcr.io/sakuzypeng/dee-fex-bundled:phase2-balanced-v5`  
   - 稳定别名：`ghcr.io/sakuzypeng/dee-fex-bundled:phase2-balanced`（已切到 `v5`）  
   - 追溯标签：`ghcr.io/sakuzypeng/dee-fex-bundled:phase2-balanced-v5-cmdfix`  
   - 远端 digest：`sha256:86186fcb4c0f7006ed4144bd06d05fd451e1eb03838112baee89e10efec51850`  
   - 本地镜像体积（`docker images`）：`356MB`  
   - 压缩后体积（GHCR manifest，`config + layers`）：`116.67 MiB`
