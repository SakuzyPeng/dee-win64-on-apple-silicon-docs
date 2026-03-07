# DEE FEX 容器运行指南（ARM64）

## 目标
本指南用于在 Apple Silicon 上用 `FEX + Wine + linux/arm64` 运行 DEE CLI 编码任务，并提供可迁移的分发流程。

采用 FEX 的战略目的：降低对 `Rosetta 2` 的依赖，提前应对苹果未来可能弃用 `Rosetta 2` 的风险。

适用范围：
- 纯命令行编码任务（无 GUI 依赖）
- 以容器化迁移为主
- 默认分发包不包含 `dolby_encoding_engine`

不在本指南中展开：
- 历史实验过程与逐轮基准明细
- 普通 Wine 方案对比

## 当前可用结论（2026-03-07）
- `dee.exe --help` 可运行，退出码 `0`
- `ADM -> Atmos DDP EC3` 真实编码可运行，退出码 `0`
- `TSO Emulation: Enabled`
- FEX/Wine thunks 在位（`libarm64ecfex.dll`、`libwow64fex.dll`、`GuestThunks`）

## 关键脚本
初始化与运行：
- `scripts/build_fex_lab.sh`
- `scripts/prepare_fex_rootfs.sh`
- `scripts/install_wine_in_fex_rootfs_chroot.sh`
- `scripts/run_fex_lab_probe.sh`
- `scripts/run_dee_with_fex.sh`
- `scripts/run_dee_with_fex_persistent.sh`

裁剪：
- `scripts/prune_fex_conservative.sh`
- `scripts/prune_fex_medium.sh`
- `scripts/prune_fex_aggressive.sh`

分发：
- `scripts/build_fex_release_bundle.sh`
- `scripts/unpack_fex_release_bundle.sh`

## 一次性初始化
1. 构建实验镜像
```bash
./scripts/build_fex_lab.sh
```

2. 准备 RootFS（自动下载并解压 Ubuntu 24.04）
```bash
./scripts/prepare_fex_rootfs.sh
```

3. 在 RootFS 中安装并修复 Wine 布局
```bash
./scripts/install_wine_in_fex_rootfs_chroot.sh
```

4. 基础探测
```bash
./scripts/run_fex_lab_probe.sh
```

## 日常运行
CLI 冒烟：
```bash
./scripts/run_dee_with_fex.sh --help
```

ADM 示例编码：
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

## 运行约定（避免回归）
`run_dee_with_fex.sh` 已内置：
- `WINEPREFIX` 初始化
- 盘符映射
- `c:` -> `../drive_c`
- `z:` -> `FEX_ROOTFS`
- `y:` -> `/workspace`
- 首次自动 `wineboot -u`

若映射缺失，典型报错：
- `could not load kernel32.dll, status c0000135`

## 分发与迁移
### 构建分发包（默认不含 DEE）
```bash
./scripts/build_fex_release_bundle.sh --tag local_test
```

输出：
- `release/dee-fex-runtime-local_test/`
- `release/latest/`（固定发布目录）

`release/latest/` 固定文件名：
- `dee-fex-runtime.tar.zst`
- `dee-fex-runtime.sha256`
- `dee-fex-runtime.manifest.txt`

可选：包含本地 DEE 引擎（仅内部分发场景）
```bash
./scripts/build_fex_release_bundle.sh --include-engine --tag with_engine
```

### 解包与校验
```bash
./scripts/unpack_fex_release_bundle.sh \
  --archive release/latest/dee-fex-runtime.tar.zst \
  --sha256 release/latest/dee-fex-runtime.sha256 \
  --dest /tmp/dee-fex-runtime-test
```

若分发包不含 DEE，运行时指定本机引擎目录：
```bash
DEE_DIR=/abs/path/to/dolby_encoding_engine \
  bash /tmp/dee-fex-runtime-test/runtime/scripts/run_dee_with_fex.sh --help
```

## 验收清单
1. 功能冒烟
```bash
./scripts/run_dee_with_fex.sh --help
./scripts/run_dee_with_fex.sh --print-stages
```

2. 真实编码
- `ADM -> EC3` 成功
- 输出文件与日志存在

3. TSO 检查
```bash
docker run --rm --platform linux/arm64 dee-fex-lab:local \
  bash -lc 'FEXGetConfig --tso-emulation-info'
```
应包含：`TSO Emulation: Enabled`

4. Thunks 检查
```bash
docker run --rm --platform linux/arm64 dee-fex-lab:local \
  bash -lc 'ls -l /usr/lib/wine/aarch64-windows/libarm64ecfex.dll /usr/lib/wine/aarch64-windows/libwow64fex.dll'
```
并确认目录存在：
- `/usr/share/fex-emu/GuestThunks`
- `/usr/share/fex-emu/GuestThunks_32`
- `/usr/share/fex-emu/ThunksDB.json`

## 体积基线（不含 DEE，2026-03-07）
- 分发包：`release/latest/dee-fex-runtime.tar.zst` 约 `150M`
- 解包 RootFS：约 `573M`
- 运行镜像：`dee-fex-lab:local` 约 `632MB`
- 本机完整运行环境（镜像 + RootFS）：约 `1.2GB`

## 裁剪策略（推荐）
推荐顺序：`conservative -> medium -> aggressive`

命令：
```bash
./scripts/prune_fex_conservative.sh --apply
./scripts/prune_fex_medium.sh --apply
./scripts/prune_fex_aggressive.sh --apply
```

每步裁剪后都执行验收清单。需要回滚时，使用对应脚本的 `--rollback`。

说明：
- `aggressive` 体积最小，但可能有轻微性能回退
- 如果更重视性能稳定性，优先停在 `medium`

## 常见问题
1. `FEXRootFSFetcher` 在无交互 tty 场景可能异常
2. `--as-is` 依赖 FUSE，普通容器环境通常不可用
3. 无 GUI 时的 `nodrv_CreateWindow` 日志通常可忽略
4. XML 模板中的 `PATH/FILE_NAME` 占位符必须显式覆盖
5. 打包报 `No space left on device` 时，清理 `tmp_release_stage/` 与旧 `release/*` 产物

## 维护原则
- 这是一份操作指南，只保留可执行流程与验收标准
- 过程性实验细节请通过 Git 提交历史追溯
