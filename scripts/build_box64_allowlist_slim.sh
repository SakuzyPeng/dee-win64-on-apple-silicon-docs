#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_IMAGE="${SOURCE_IMAGE:-dee-box64-lab:local}"
TARGET_IMAGE="${TARGET_IMAGE:-dee-box64-lab:slim-local}"
ALLOWLIST="${ALLOWLIST:-$ROOT_DIR/tmp_box64_prune/allowlist/runtime-allowlist.txt}"
PLATFORM="${PLATFORM:-linux/arm64}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/tmp_box64_prune/slim-build}"

usage() {
  cat <<'EOF'
Usage:
  scripts/build_box64_allowlist_slim.sh [options]

Options:
  --source-image TAG   source image containing full runtime
  --target-image TAG   output slim image tag
  --allowlist FILE     runtime allowlist file
  --artifact-dir DIR   output directory for build artifacts
  --platform PLAT      docker platform (default: linux/arm64)
  -h, --help           show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-image)
      shift
      SOURCE_IMAGE="${1:-}"
      ;;
    --target-image)
      shift
      TARGET_IMAGE="${1:-}"
      ;;
    --allowlist)
      shift
      ALLOWLIST="${1:-}"
      ;;
    --artifact-dir)
      shift
      ARTIFACT_DIR="${1:-}"
      ;;
    --platform)
      shift
      PLATFORM="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

to_abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$ROOT_DIR/$p"
  fi
}

ALLOWLIST="$(to_abs_path "$ALLOWLIST")"
ARTIFACT_DIR="$(to_abs_path "$ARTIFACT_DIR")"

[[ -f "$ALLOWLIST" ]] || { echo "Allowlist file not found: $ALLOWLIST" >&2; exit 1; }
[[ -s "$ALLOWLIST" ]] || { echo "Allowlist is empty: $ALLOWLIST" >&2; exit 1; }

if ! docker image inspect "$SOURCE_IMAGE" >/dev/null 2>&1; then
  echo "Source image not found: $SOURCE_IMAGE" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RESOLVED_ALLOWLIST="$ARTIFACT_DIR/runtime-allowlist.resolved.txt"
MANIFEST="$ARTIFACT_DIR/prune-manifest.md"

docker run --rm --platform "$PLATFORM" \
  -v "$ALLOWLIST:/tmp/allowlist.txt:ro" \
  "$SOURCE_IMAGE" bash -lc '
    set -euo pipefail
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if [[ -f "$p" || -L "$p" ]]; then
        echo "$p"
      fi
    done < /tmp/allowlist.txt
  ' | sort -u > "$RESOLVED_ALLOWLIST"

if [[ ! -s "$RESOLVED_ALLOWLIST" ]]; then
  echo "Resolved allowlist is empty after source-image filtering." >&2
  exit 1
fi

cp "$RESOLVED_ALLOWLIST" "$TMP_DIR/allowlist.txt"

cat > "$TMP_DIR/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1.7
ARG SOURCE_IMAGE
FROM --platform=linux/arm64 ${SOURCE_IMAGE} AS source
COPY allowlist.txt /tmp/allowlist.txt
RUN set -eux; \
    mkdir -p /opt/slimroot; \
    while IFS= read -r p; do \
      [ -n "$p" ] || continue; \
      case "$p" in /bin/*) continue ;; esac; \
      [ -e "$p" ] || continue; \
      cp -aL --parents "$p" /opt/slimroot; \
    done < /tmp/allowlist.txt; \
    copy_bin_with_libs() { \
      b="$1"; \
      [ -e "$b" ] || return 0; \
      cp -aL --parents "$b" /opt/slimroot; \
      ldd "$b" 2>/dev/null | awk '{ \
        if ($2 == "=>" && $3 ~ /^\/.*/) print $3; \
        else if ($1 ~ /^\/.*/) print $1; \
      }' | sort -u | while IFS= read -r lib; do \
        [ -n "$lib" ] || continue; \
        [ -e "$lib" ] || continue; \
        cp -aL --parents "$lib" /opt/slimroot; \
      done; \
    }; \
    for b in \
      /usr/local/bin/box64 \
      /usr/lib/wine/wine64 \
      /usr/lib/wine/wineserver \
      /usr/lib/wine/wineserver64 \
      /usr/lib/x86_64-linux-gnu/wine/x86_64-windows/services.exe \
      /usr/lib/x86_64-linux-gnu/wine/x86_64-windows/wineboot.exe \
      /usr/bin/timeout \
      /usr/bin/mkdir \
      /usr/bin/ln \
      /usr/bin/touch \
      /bin/sh \
      /bin/bash; do \
      copy_bin_with_libs "$b"; \
    done; \
    for d in \
      /usr/lib/wine \
      /usr/lib/x86_64-linux-gnu/wine \
      /usr/share/wine \
      /etc/fonts; do \
      [ -e "$d" ] || continue; \
      cp -aL --parents "$d" /opt/slimroot; \
    done; \
    mkdir -p /opt/slimroot/tmp /opt/slimroot/var/tmp; \
    chmod 1777 /opt/slimroot/tmp /opt/slimroot/var/tmp; \
    if [ -d /opt/box64-prune ]; then \
      cp -a --parents /opt/box64-prune /opt/slimroot; \
    fi

FROM scratch
LABEL org.opencontainers.image.source="https://github.com/SakuzyPeng/dee-win64-on-apple-silicon-docs"
COPY --from=source /opt/slimroot/ /
WORKDIR /workspace
CMD ["/bin/bash"]
EOF

echo "Building slim image '$TARGET_IMAGE' from '$SOURCE_IMAGE'..."
time docker build \
  --platform "$PLATFORM" \
  --progress=plain \
  --tag "$TARGET_IMAGE" \
  --build-arg SOURCE_IMAGE="$SOURCE_IMAGE" \
  "$TMP_DIR"

{
  echo "# Box64 Slim Prune Manifest"
  echo ""
  echo "- Build time: \`$(date '+%Y-%m-%d %H:%M:%S %z')\`"
  echo "- Source image: \`$SOURCE_IMAGE\`"
  echo "- Target image: \`$TARGET_IMAGE\`"
  echo "- Platform: \`$PLATFORM\`"
  echo "- Requested allowlist count: \`$(wc -l < "$ALLOWLIST" | tr -d ' ')\`"
  echo "- Resolved allowlist count: \`$(wc -l < "$RESOLVED_ALLOWLIST" | tr -d ' ')\`"
  echo ""
  echo "Artifacts:"
  echo "- \`$ALLOWLIST\`"
  echo "- \`$RESOLVED_ALLOWLIST\`"
} > "$MANIFEST"

echo "Slim image build complete: $TARGET_IMAGE"
echo "Artifacts: $ARTIFACT_DIR"
