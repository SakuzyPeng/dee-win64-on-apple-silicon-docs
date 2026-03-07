# DEE 容器化方案：自编译精简 Wine（实测笔记）

## 1. 目标

在 Docker 容器内运行 `dolby_encoding_engine`（Windows x64），通过自编译精简版 Wine 9.0 减小镜像体积，并完成实际编码任务（`ADM WAV -> EC3`）。

该方案是非 FEX 路线，运行依赖 `linux/amd64 + Rosetta 2` 转译。

---

## 2. 最终结论

自编译精简 Wine 9.0 容器（`dee-wine-minimal`）可稳定运行 `dee.exe`：

1. `dee.exe --print-stages -l license.lic` 正常加载插件与授权。
2. 使用模板实际编码 `testADM.wav -> testADM_out.ec3` 成功，进度 100%。
3. 镜像体积 **442 MB**，较 Debian 官方 `wine64` 包方案（886 MB）缩小约 50%。

---

## 3. 环境

1. 硬件：Apple Silicon Mac
2. 容器运行时：OrbStack（Docker 兼容）
3. 容器平台：`linux/amd64`（经 Rosetta 模拟）
4. Wine 版本：9.0（源码自编译，64-bit only）
5. 镜像基础层：`debian:bookworm-slim`

---

## 4. 方案对比

| 方案 | 镜像大小 | 运行时依赖包数 | 构建方式 |
|---|---|---|---|
| Debian `wine64` 包 | 886 MB | ~80 | `apt install wine64` |
| **自编译精简 Wine 9.0** | **442 MB** | **4** | 源码编译，禁用无关子系统，strip 二进制 |

### 去掉的 Wine 子系统

DEE 是纯 CLI 音频编码工具，以下子系统对其无用：

| 去掉的子系统 | 对应 configure 参数 |
|---|---|
| X11 / Wayland 显示 | `--without-x --without-wayland` |
| ALSA / PulseAudio / OSS 音频硬件 | `--without-alsa --without-pulse --without-oss` |
| GStreamer 多媒体管道 | `--without-gstreamer` |
| USB / V4L2 / gphoto 硬件 | `--without-usb --without-v4l2 --without-gphoto` |
| OpenCL / OpenAL / SDL | `--without-opencl --without-openal --without-sdl` |
| LDAP / Kerberos / CAPI | `--without-ldap --without-krb5 --without-capi` |
| VKD3D / fontconfig | `--without-vkd3d --without-fontconfig` |

### 运行时仅需 4 个包

```
libfreetype6  libxml2  zlib1g  libgnutls30
```

---

## 5. 裁剪策略

### 5.1 编译阶段裁剪

| 策略 | 方法 | 预期收益 |
|---|---|---|
| 禁用无关子系统 | `./configure --without-x --without-gstreamer ...` | 减少 build 时间，减少中间产物 |
| 关闭调试信息 | `CFLAGS="-O2" CXXFLAGS="-O2"`（不加 `-g`） | 编译产物从 ~1.8 GB 压到 ~800 MB |
| 并行编译 | `make -j$(nproc)` | 利用多核加速（2 核约 35 分钟） |

### 5.2 安装阶段裁剪

```bash
# Stage 1 完成后
make install DESTDIR=/wine-root && \
  # 去掉所有二进制和库的调试符号
  find /wine-root -type f \( -name '*.so*' -o -name 'wine*' \) -exec strip -s {} \; && \
  # 删除多余文档和本地化文件
  rm -rf /wine-root/usr/share/man \
         /wine-root/usr/share/doc \
         /wine-root/usr/share/locale
```

**收益**：
- `strip -s`：删除 ELF 头中的所有符号，减少 ~5~10%
- 删除 man/doc/locale：减少 ~10~20 MB

### 5.3 运行时依赖最小化

| 项 | Debian wine64 包 | 自编译版本 |
|---|---|---|
| 运行时包 | ~80 个 | 4 个 |
| 包列表 | X11、GStreamer、ALSA、Kerberos 等 | `libfreetype6` `libxml2` `zlib1g` `libgnutls30` |

DEE 只需最基础的运行库，无 GUI、无音频硬件、无网络库。

---

## 6. Dockerfile

文件：`Dockerfile.minimal-wine`

```dockerfile
# Stage 1: Build Wine 9.0 (64-bit only, headless minimal)
FROM --platform=linux/amd64 debian:bookworm AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential flex bison wget ca-certificates pkg-config \
    libfreetype-dev libxml2-dev zlib1g-dev libgnutls28-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN wget -q https://dl.winehq.org/wine/source/9.0/wine-9.0.tar.xz && \
    tar xf wine-9.0.tar.xz && rm wine-9.0.tar.xz

WORKDIR /build/wine-9.0
RUN ./configure \
      --prefix=/usr --enable-win64 --disable-win16 --disable-tests \
      --without-x --without-wayland \
      --without-alsa --without-pulse --without-oss \
      --without-gstreamer \
      --without-usb --without-v4l2 --without-opencl --without-openal \
      --without-cups --without-sane --without-dbus \
      --without-netapi --without-pcap --without-krb5 \
      --without-ldap --without-capi --without-gphoto \
      --without-sdl --without-vkd3d --without-fontconfig \
      CFLAGS="-O2" CXXFLAGS="-O2" && \
    make -j$(nproc) && \
    make install DESTDIR=/wine-root

# Stage 2: Minimal runtime
FROM --platform=linux/amd64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEDEBUG=fixme-all \
    WINEPREFIX=/wine

COPY --from=builder /wine-root/usr /usr

RUN apt-get update && apt-get install -y --no-install-recommends \
    libfreetype6 libxml2 zlib1g libgnutls30 \
    && rm -rf /var/lib/apt/lists/*

RUN wine64 wineboot --init 2>/dev/null; wineserver -w; true

WORKDIR /dee
ENTRYPOINT ["wine64", "dee.exe"]
CMD ["--help"]
```

---

## 7. 构建方式

由于 Mac 本地无法访问 Docker Hub，在远端 Linux 服务器构建后流式传回：

```bash
# 传 Dockerfile 到远端并构建
scp Dockerfile.minimal-wine user@remote:/tmp/dee-wine-minimal.Dockerfile
ssh user@remote "docker build --platform linux/amd64 \
  -t dee-wine-minimal \
  -f /tmp/dee-wine-minimal.Dockerfile /tmp"

# 压缩流式传回本地（无需落盘）
ssh user@remote "docker save dee-wine-minimal | gzip" | docker load
```

> 注意：Wine 9.0 源码编译约需 **30~40 分钟**（2 核服务器），远端磁盘需预留约 **3 GB** 空闲空间用于中间产物。

---

## 8. 使用方式

DEE 二进制挂载进容器，不打包进镜像（方便更新，也规避版权问题）。

### 验证 license

```bash
docker run --rm --platform linux/amd64 \
  -v /path/to/dolby_encoding_engine:/dee \
  dee-wine-minimal \
  --print-stages -l license.lic
```

### 实际编码

```bash
docker run --rm --platform linux/amd64 \
  -v /path/to/dee-win:/path/to/dee-win \
  -v /path/to/dolby_encoding_engine:/dee \
  dee-wine-minimal \
  --xml "Z:/path/to/dee-win/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml" \
  -l license.lic \
  --progress --stdout
```

> **路径说明**：Wine 的 `Z:` 盘映射到容器内的根目录 `/`。XML 模板中引用的宿主机路径需以相同路径挂载进容器，使 `Z:/path/to/...` 能正确解析。

---

## 9. 验证结果

| 测试项 | 结果 |
|---|---|
| `dee.exe --help` | ✅ |
| `--print-stages -l license.lic`（全插件加载）| ✅ |
| `testADM.wav -> testADM_out.ec3` 实际编码 | ✅ |
| 输出文件大小 | 2.7 MB |
| 编码耗时 | ~15 秒 |

---

## 10. 注意事项

1. **磁盘空间**：
   - 镜像解压后大小：442 MB（`docker images` 显示值）
   - 本地加载约需 500 MB 可用空间
   - 远端构建需 3 GB（中间产物）
2. **平台限制**：`linux/amd64` 镜像在 Apple Silicon 上经 Rosetta 模拟运行，有额外性能开销。
3. **个人使用推荐**：单机场景下，`~/bin/dee` 脚本方案（直接调用 `gcenx/wine`）开销更低，无需容器。容器方案适合团队共享或 CI/CD 环境。
