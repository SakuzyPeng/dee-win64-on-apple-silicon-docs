# DEE Containerized: Self-Compiled Minimal Wine (Practical Notes)

## 1. Goal

Run `dolby_encoding_engine` (Windows x64) inside a Docker container using a self-compiled, stripped-down Wine 9.0, reducing image size while completing a real encoding workflow (`ADM WAV -> EC3`).

This is a non-FEX track and depends on `linux/amd64 + Rosetta 2` translation.

---

## 2. Final Result

The self-compiled minimal Wine 9.0 container (`dee-wine-minimal`) runs `dee.exe` reliably:

1. `dee.exe --print-stages -l license.lic` loads all plugins and the license correctly.
2. A real template-based encode (`testADM.wav -> testADM_out.ec3`) completes with 100% progress.
3. Image size: **442 MB** — approximately 50% smaller than the Debian `wine64` package approach (886 MB).

---

## 3. Environment

1. Hardware: Apple Silicon Mac
2. Container runtime: OrbStack (Docker-compatible)
3. Container platform: `linux/amd64` (emulated via Rosetta)
4. Wine version: 9.0 (compiled from source, 64-bit only)
5. Base image: `debian:bookworm-slim`

---

## 4. Approach Comparison

| Approach | Image size | Runtime packages | Build method |
|---|---|---|---|
| Debian `wine64` package | 886 MB | ~80 | `apt install wine64` |
| **Self-compiled minimal Wine 9.0** | **442 MB** | **4** | Source build, unused subsystems disabled, binaries stripped |

### Disabled Wine Subsystems

DEE is a headless CLI audio encoder. The following subsystems are not needed:

| Subsystem | configure flag |
|---|---|
| X11 / Wayland display | `--without-x --without-wayland` |
| ALSA / PulseAudio / OSS audio | `--without-alsa --without-pulse --without-oss` |
| GStreamer multimedia pipeline | `--without-gstreamer` |
| USB / V4L2 / gphoto hardware | `--without-usb --without-v4l2 --without-gphoto` |
| OpenCL / OpenAL / SDL | `--without-opencl --without-openal --without-sdl` |
| LDAP / Kerberos / CAPI | `--without-ldap --without-krb5 --without-capi` |
| VKD3D / fontconfig | `--without-vkd3d --without-fontconfig` |

### Only 4 runtime packages required

```
libfreetype6  libxml2  zlib1g  libgnutls30
```

---

## 5. Dockerfile

File: `Dockerfile.minimal-wine`

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

## 6. Optimization Techniques

### 6.1 Compilation-stage shrinkage

| Technique | Method | Expected benefit |
|---|---|---|
| Disable unneeded subsystems | `./configure --without-x --without-gstreamer ...` | Reduce build time, fewer intermediate artifacts |
| No debug symbols | `CFLAGS="-O2" CXXFLAGS="-O2"` (no `-g`) | Build artifacts: ~1.8 GB → ~800 MB |
| Parallel build | `make -j$(nproc)` | Faster on multi-core systems (~35 min on 2 cores) |

### 6.2 Install-stage shrinkage

```bash
# After Stage 1 build completes
make install DESTDIR=/wine-root && \
  # Strip all debug symbols from binaries and shared libraries
  find /wine-root -type f \( -name '*.so*' -o -name 'wine*' \) -exec strip -s {} \; && \
  # Remove docs, man pages, and locales (unused at runtime)
  rm -rf /wine-root/usr/share/man \
         /wine-root/usr/share/doc \
         /wine-root/usr/share/locale
```

**Savings:**
- `strip -s`: Removes all ELF symbols, reduces size by ~5–10%
- Removing man/doc/locale: Saves ~10–20 MB

### 6.3 Minimal runtime dependencies

| Item | Debian wine64 package | Self-compiled |
|---|---|---|
| Runtime packages | ~80 | 4 |
| Package list | X11, GStreamer, ALSA, Kerberos, etc. | `libfreetype6` `libxml2` `zlib1g` `libgnutls30` |

DEE needs only core runtime libraries—no GUI, no audio hardware drivers, no network libraries.

---

## 7. Build Process

Docker Hub was unreachable on the Mac, so the image was built on a remote Linux server and streamed back:

```bash
# Copy Dockerfile to remote server and build
scp Dockerfile.minimal-wine user@remote:/tmp/dee-wine-minimal.Dockerfile
ssh user@remote "docker build --platform linux/amd64 \
  -t dee-wine-minimal \
  -f /tmp/dee-wine-minimal.Dockerfile /tmp"

# Stream the image back to local machine (no intermediate file)
ssh user@remote "docker save dee-wine-minimal | gzip" | docker load
```

> **Note:** Compiling Wine 9.0 from source takes approximately **30–40 minutes** on a 2-core server. The remote server needs about **3 GB** of free disk space for intermediate build artifacts.

---

## 8. Usage

DEE binaries are bind-mounted into the container at runtime rather than baked into the image, making updates easy and avoiding distribution of proprietary binaries.

### Verify license

```bash
docker run --rm --platform linux/amd64 \
  -v /path/to/dolby_encoding_engine:/dee \
  dee-wine-minimal \
  --print-stages -l license.lic
```

### Real encoding job

```bash
docker run --rm --platform linux/amd64 \
  -v /path/to/dee-win:/path/to/dee-win \
  -v /path/to/dolby_encoding_engine:/dee \
  dee-wine-minimal \
  --xml "Z:/path/to/dee-win/dolby_encoding_engine/xml_templates/encode_to_atmos_ddp/music/album_encode_to_atmos_ddp_ec3.test.xml" \
  -l license.lic \
  --progress --stdout
```

> **Path note:** Wine maps the container's root `/` to the `Z:` drive. Any host paths referenced in XML templates must be mounted at the same path inside the container so that `Z:/path/to/...` resolves correctly.

---

## 9. Verification Results

| Test | Result |
|---|---|
| `dee.exe --help` | ✅ |
| `--print-stages -l license.lic` (all plugins loaded) | ✅ |
| `testADM.wav -> testADM_out.ec3` real encode | ✅ |
| Output file size | 2.7 MB |
| Encoding time | ~15 seconds |

---

## 10. Notes

1. **Disk space:**
   - Image size (uncompressed): 442 MB (as shown by `docker images`)
   - Loading locally requires ~500 MB of free space
   - Remote build requires ~3 GB (for intermediate artifacts)
2. **Platform emulation:** The `linux/amd64` image runs on Apple Silicon via Rosetta, which adds some performance overhead.
3. **Single-machine recommendation:** For personal use on a Mac where `gcenx/wine` is already installed, the `~/bin/dee` wrapper script is lighter with no container overhead. The Docker approach is suited for team environments or CI/CD pipelines.
