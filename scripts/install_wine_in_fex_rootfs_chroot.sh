#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_BASE="${ROOTFS_BASE:-$ROOT_DIR/tmp_fex_rootfs}"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOTFS_BASE/RootFS/Ubuntu_24_04}"

if [[ ! -d "$ROOTFS_DIR" ]]; then
  echo "RootFS directory not found: $ROOTFS_DIR" >&2
  echo "Run scripts/prepare_fex_rootfs.sh first." >&2
  exit 1
fi

echo "Installing wine packages into rootfs via amd64 chroot: $ROOTFS_DIR"
docker run --rm --platform linux/amd64 \
  -v "$ROOTFS_DIR:/rootfs" \
  ubuntu:24.04 bash -lc '
    set -euo pipefail

    cp -f /etc/resolv.conf /rootfs/etc/resolv.conf
    mkdir -p /rootfs/tmp /rootfs/var/tmp /rootfs/dev /rootfs/run /rootfs/var/lib/apt/lists/partial
    chmod 1777 /rootfs/tmp /rootfs/var/tmp
    : > /rootfs/dev/null
    : > /rootfs/dev/zero
    : > /rootfs/dev/random
    : > /rootfs/dev/urandom
    : > /rootfs/run/adduser

    if [ ! -x /rootfs/usr/bin/logger ]; then
      cat > /rootfs/usr/bin/logger <<'"'"'SH'"'"'
#!/bin/sh
exit 0
SH
      chmod +x /rootfs/usr/bin/logger
    fi

    rm -f /rootfs/var/lib/apt/lists/lock /rootfs/var/cache/apt/archives/lock /rootfs/var/lib/dpkg/lock* || true
    chroot /rootfs /usr/bin/getent group messagebus >/dev/null || chroot /rootfs /usr/sbin/groupadd -r messagebus

    chroot /rootfs /usr/bin/apt-get update >/dev/null
    chroot /rootfs /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install -y --no-install-recommends \
      wine \
      wine64 \
      wine64-preloader \
      wine32:i386

    mkdir -p /rootfs/usr/lib/wine /rootfs/usr/bin
    ln -sf /usr/lib/x86_64-linux-gnu/wine/x86_64-unix /rootfs/usr/lib/wine/x86_64-unix
    ln -sf /usr/lib/x86_64-linux-gnu/wine/x86_64-windows /rootfs/usr/lib/wine/x86_64-windows
    ln -sf /usr/lib/i386-linux-gnu/wine/i386-unix /rootfs/usr/lib/wine/i386-unix
    ln -sf /usr/lib/i386-linux-gnu/wine/i386-windows /rootfs/usr/lib/wine/i386-windows
    ln -sf /usr/lib/wine/wine64 /rootfs/usr/bin/wine64
  '

echo "Wine install complete (chroot path)."
