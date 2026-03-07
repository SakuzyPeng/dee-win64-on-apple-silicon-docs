# Platform: linux/amd64 (required — DEE is Windows x64, runs via Wine on amd64)
FROM --platform=linux/amd64 debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/SakuzyPeng/dee-win64-on-apple-silicon-docs"

ENV DEBIAN_FRONTEND=noninteractive \
    WINEDEBUG=fixme-all \
    WINEPREFIX=/wine

# Install wine64 only (DEE is x64-only, no need for i386/wine32)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wine64 \
        wget \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    which wine64 >/dev/null || ln -sf /usr/lib/wine/wine64 /usr/bin/wine64 && \
    which wineserver >/dev/null || ln -sf /usr/lib/wine/wineserver64 /usr/bin/wineserver

# Initialize Wine prefix (64-bit only)
RUN wine64 wineboot --init 2>/dev/null; wineserver -w; true

# Install VC++ 2022 x64 redistributable (VCRUNTIME140 / MSVCP140 / UCRT)
RUN wget -q "https://aka.ms/vs/17/release/vc_redist.x64.exe" -O /tmp/vcredist.exe && \
    [ -f /tmp/vcredist.exe ] && \
    wine64 /tmp/vcredist.exe /install /quiet /norestart 2>/dev/null && \
    wineserver -w && \
    rm /tmp/vcredist.exe && \
    echo "VC++ redist installed" >/tmp/vcredist_ok

# DEE binaries are mounted at runtime via -v, not baked into the image
WORKDIR /dee

ENTRYPOINT ["wine64", "dee.exe"]
CMD ["--help"]
