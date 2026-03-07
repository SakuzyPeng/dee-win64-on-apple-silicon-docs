# DEE 容器方案（FEX + Wine / ARM64）

## 当前状态（2026-03-07）

`FEX + Wine + linux/arm64` 方案已跑通：

1. `dee.exe --help` 可执行（退出码 `0`）。
2. 真实编码可执行：`testADM.wav -> testADM_fex_atmos.ec3`（退出码 `0`）。
3. `TSO Emulation: Enabled`（`FEXGetConfig --tso-emulation-info`）。
4. FEX/Wine thunk 组件在位（`libarm64ecfex.dll`、`libwow64fex.dll`、`GuestThunks`）。

这份文档用于固化“当前可复现方案”。

## 相关文件

- `Dockerfile.fex-lab`
- `scripts/build_fex_lab.sh`
- `scripts/prepare_fex_rootfs.sh`
- `scripts/install_wine_in_fex_rootfs_chroot.sh`
- `scripts/run_fex_lab_probe.sh`
- `scripts/run_dee_with_fex.sh`
- `scripts/prune_fex_rootfs.sh`
- `scripts/prune_fex_wine32.sh`
- `scripts/prune_fex_i386_runtime.sh`
- `scripts/prune_fex_wine64_windows.sh`

## 一次性准备

### 1) 构建镜像

```bash
./scripts/build_fex_lab.sh
```

### 2) 准备 RootFS（下载 + 解压）

```bash
./scripts/prepare_fex_rootfs.sh
```

说明：

- RootFS URL 从 `https://rootfs.fex-emu.gg/RootFS_links.json` 自动选择（`ubuntu/24.04/squashfs`）。
- 已下载/已解压会复用，不重复下载。

### 3) 向 RootFS 注入 Wine

```bash
./scripts/install_wine_in_fex_rootfs_chroot.sh
```

该脚本会在 `amd64 chroot` 中安装并修复 Wine 运行布局（含 `wine` 元包和 `i386` 路径链接）。

### 4) 基础探测

```bash
./scripts/run_fex_lab_probe.sh
```

## 运行方式

### 1) CLI 冒烟

```bash
./scripts/run_dee_with_fex.sh --help
```

### 2) 真实编码（ADM 类型样例）

```bash
./scripts/run_dee_with_fex.sh \
  --xml y:/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml \
  --input-audio y:/testADM.wav \
  --output y:/testADM_fex_atmos.ec3 \
  --temp y:/tmp_dee \
  --log-file y:/testADM_fex_atmos.log \
  --stdout \
  --verbose info
```

## 本次验证结果

### 功能结果

1. `dee.exe --help`：通过，退出码 `0`。
2. `testADM.wav -> testADM_fex_atmos.ec3`：通过，退出码 `0`。
3. 编码日志显示 `encode_to_atmos_ddp` 流程完整，进度到 `100%`。

### 性能快照（当前机器）

1. `--help` 热启动：`real 1.95s`。
2. 真实编码外层总耗时：`real 17.94s`。
3. DEE 内部任务耗时：`Job execution took 11 seconds`。

### 产物

- `testADM_fex_atmos.ec3`
- `testADM_fex_atmos.log`

## 关键实现点（避免回归）

`run_dee_with_fex.sh` 已内置并自动处理：

1. `WINEPREFIX` 初始化。
2. 盘符映射：
   - `c:` -> `../drive_c`
   - `z:` -> `FEX_ROOTFS`
   - `y:` -> `/workspace`
3. 首次执行 `wineboot -u` 进行前缀初始化。

如果这组映射丢失，典型报错是 `could not load kernel32.dll, status c0000135`。

## TSO / Thunks 检查

### TSO

```bash
docker run --rm --platform linux/arm64 dee-fex-lab:local \
  bash -lc 'FEXGetConfig --tso-emulation-info'
```

关键字段应包含：

- `TSO Emulation: Enabled`

### Thunks

```bash
docker run --rm --platform linux/arm64 dee-fex-lab:local \
  bash -lc 'ls -l /usr/lib/wine/aarch64-windows/libarm64ecfex.dll /usr/lib/wine/aarch64-windows/libwow64fex.dll'
```

以及：

- `/usr/share/fex-emu/GuestThunks`
- `/usr/share/fex-emu/GuestThunks_32`
- `/usr/share/fex-emu/ThunksDB.json`

## 已知问题

1. `FEXRootFSFetcher` 在无输入 `tty` 场景可能触发 `std::invalid_argument`。
2. `--as-is` 模式依赖 FUSE，普通容器环境通常不可用。
3. 无 GUI 环境会出现 `nodrv_CreateWindow` 日志，对 CLI 编码任务通常无影响。
4. 通用 XML 模板中的 `PATH/FILE_NAME` 占位符需要显式覆盖，否则会报目录不存在。

## 下一步

1. 先做标准化性能基线脚本（冷启动、热启动、真实编码）。
2. 再按基线做精简（RootFS 与 Wine 组件），每步回归功能与耗时。

## 已验证裁剪记录（2026-03-07）

### 1) wine32 组件裁剪（已验证）

```bash
./scripts/prune_fex_wine32.sh --apply
```

结果：

1. RootFS 约回收 `559688 KB`。
2. `run_dee_with_fex*.sh` 默认已切到 `WINE_BIN=/usr/lib/wine/wine64`。
3. `--help`、`--print-stages`、`ADM -> EC3` 编码均通过。

### 2) i386 Linux 运行库裁剪（已验证）

```bash
./scripts/prune_fex_i386_runtime.sh --apply
```

结果：

1. RootFS 从 `2675196 KB` 降至 `2101276 KB`，约回收 `573920 KB`。
2. `--help`、`--print-stages`、`ADM -> EC3` 编码均通过。
3. 可回滚：

```bash
./scripts/prune_fex_i386_runtime.sh --rollback
```

### 3) 裁剪后 FEX 基线（RUNS=3）

运行命令：

```bash
RUNS=3 MODE=fex WINE_BIN=/usr/lib/wine/wine64 ./scripts/benchmark_fex_native_baseline.sh
```

Run ID: `20260307_201544`

1. `help_cold`: `12.903s`
2. `help_warm`: `1.993s`
3. `encode_adm_to_ec3`: `17.050s`
4. `mean_dee_job_s`: `10.000s`

### 4) wine64 Windows 模块白名单裁剪（实验通过，含冷启动修复）

```bash
./scripts/prune_fex_wine64_windows.sh --collect
./scripts/prune_fex_wine64_windows.sh --apply
```

结果：

1. `x86_64-windows` 目录从 `648520 KB` 降至 `85904 KB`，回收约 `564912 KB`。
2. 白名单保留 `48` 个模块（在基础集上补了 `newdev.dll`、`hidclass.sys`、`winebus.sys`、`winehid.sys`、`wineusb.sys`、`winexinput.sys`，用于修复冷启动超时）。
3. `--help`、`--print-stages`、`ADM -> EC3` 真实编码均通过（退出码 `0`）。
4. 回滚可用：

```bash
./scripts/prune_fex_wine64_windows.sh --rollback
```

性能观察（Run ID: `20260307_222156`）：

1. `encode_adm_to_ec3`: `18.090s`
2. `help_warm`: `2.093s`
3. `help_cold`: `7.830s`

结论：

1. 该裁剪在“固定前缀复用”和“空前缀冷启动”场景都可用。
2. 体积收益仍显著：`x86_64-windows` 由约 `633M` 降至约 `85M`。
