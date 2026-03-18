#!/usr/bin/env bash
# setup.sh — dee-win 一键配置脚本
# 在 Apple Silicon macOS 上配置 Dolby Encoding Engine (DEE) 容器运行环境
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.dee-win.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}▶${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
die()   { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }
prompt(){ echo -en "${BOLD}$*${NC} "; }

# ── 环境检查 ────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}dee-win 一键配置${NC}"
echo "────────────────────────────────"

[[ "$(uname -s)" == "Darwin" ]]  || die "此脚本仅支持 macOS。"
[[ "$(uname -m)" == "arm64"  ]]  || die "此脚本仅支持 Apple Silicon (arm64) Mac。"
ok "平台：macOS Apple Silicon"

if ! command -v docker >/dev/null 2>&1; then
  die "未找到 docker 命令。请先安装 Docker Desktop for Mac。"
fi
if ! docker info >/dev/null 2>&1; then
  die "Docker daemon 未运行。请先启动 Docker Desktop。"
fi
ok "Docker：运行中"

echo ""

# ── 路线选择 ────────────────────────────────────────────────────────────────

info "选择容器路线："
echo "  1) Box64  — 稳定推荐（x64 动态重编译，无需 Rosetta 2）[默认]"
echo "  2) FEX    — 实验性（ARM64 原生模拟，需额外准备 RootFS，约 1 GB）"
prompt "请输入 1 或 2 [1]: "
read -r ROUTE_CHOICE
ROUTE_CHOICE="${ROUTE_CHOICE:-1}"

case "$ROUTE_CHOICE" in
  1)
    DEE_MODE="box64"
    IMAGE_TAG="ghcr.io/sakuzypeng/dee-box64-lab:latest"
    ok "路线：Box64（$IMAGE_TAG）"
    ;;
  2)
    DEE_MODE="fex"
    IMAGE_TAG="ghcr.io/sakuzypeng/dee-fex-lab:latest"
    ok "路线：FEX（$IMAGE_TAG）"
    ;;
  *)
    die "无效选项：$ROUTE_CHOICE"
    ;;
esac

echo ""

# ── DEE 目录 ─────────────────────────────────────────────────────────────────

DEFAULT_DEE_DIR="$SCRIPT_DIR/dolby_encoding_engine"
info "Dolby Encoding Engine 目录（包含 dee.exe 的文件夹）"
prompt "路径 [$DEFAULT_DEE_DIR]: "
read -r DEE_DIR_INPUT
DEE_DIR="${DEE_DIR_INPUT:-$DEFAULT_DEE_DIR}"
DEE_DIR="${DEE_DIR/#\~/$HOME}"
DEE_DIR="$(eval echo "$DEE_DIR")"

[[ -d "$DEE_DIR" ]] || die "目录不存在：$DEE_DIR"
[[ -f "$DEE_DIR/dee.exe" ]] || die "dee.exe 不存在于：$DEE_DIR\n   请确认已将 Dolby Encoding Engine 解压到该目录。"

ok "DEE 目录：$DEE_DIR"

echo ""

# ── FEX RootFS 准备（仅 FEX 路线）──────────────────────────────────────────

if [[ "$DEE_MODE" == "fex" ]]; then
  ROOTFS_BASE="${ROOTFS_BASE:-$SCRIPT_DIR/tmp_fex_rootfs}"
  FEX_ROOTFS="$ROOTFS_BASE/RootFS/Ubuntu_24_04"

  info "FEX 路线需要准备 Ubuntu 24.04 RootFS（下载约 300 MB，解压后约 1 GB）"

  if [[ -d "$FEX_ROOTFS/usr" ]]; then
    ok "RootFS 已存在：$FEX_ROOTFS"
  else
    info "正在下载并解压 FEX RootFS..."
    "$SCRIPT_DIR/scripts/prepare_fex_rootfs.sh"
    ok "FEX RootFS 就绪"
  fi

  # 检查 Wine 是否已安装到 rootfs
  if [[ ! -x "$FEX_ROOTFS/usr/lib/wine/wine64" ]]; then
    info "正在向 RootFS 安装 Wine（通过 amd64 chroot）..."
    "$SCRIPT_DIR/scripts/install_wine_in_fex_rootfs_chroot.sh"
    ok "Wine 已安装到 RootFS"
  else
    ok "RootFS 内 Wine 已就绪"
  fi

  echo ""
fi

# ── Pull 镜像 ────────────────────────────────────────────────────────────────

info "正在拉取镜像：$IMAGE_TAG"
docker pull "$IMAGE_TAG"
ok "镜像已就绪"

echo ""

# ── 冒烟测试 ─────────────────────────────────────────────────────────────────

info "冒烟测试：在容器中运行 dee.exe --help ..."

SMOKE_OK=false
if [[ "$DEE_MODE" == "box64" ]]; then
  if DEE_DIR="$DEE_DIR" IMAGE_TAG="$IMAGE_TAG" \
       "$SCRIPT_DIR/scripts/run_dee_with_box64.sh" --help >/dev/null 2>&1; then
    SMOKE_OK=true
  fi
else
  if DEE_DIR="$DEE_DIR" IMAGE_TAG="$IMAGE_TAG" \
       ROOTFS_BASE="$ROOTFS_BASE" \
       "$SCRIPT_DIR/scripts/run_dee_with_fex.sh" --help >/dev/null 2>&1; then
    SMOKE_OK=true
  fi
fi

if $SMOKE_OK; then
  ok "冒烟测试通过"
else
  warn "冒烟测试未返回成功（容器首次初始化 Wine prefix 需要一些时间属正常现象）。\n   配置已保存，可稍后手动运行：dee --help"
fi

echo ""

# ── 写 .dee-win.env ──────────────────────────────────────────────────────────

info "写入配置文件：$ENV_FILE"

{
  echo "# dee-win 配置（由 setup.sh 生成，可手动修改）"
  echo "export DEE_DIR=\"$DEE_DIR\""
  if [[ "$DEE_MODE" == "box64" ]]; then
    echo "export IMAGE_TAG=\"$IMAGE_TAG\""
  else
    echo "export IMAGE_TAG=\"$IMAGE_TAG\""
    echo "export ROOTFS_BASE=\"$ROOTFS_BASE\""
  fi
} > "$ENV_FILE"

ok "已写入 $ENV_FILE"

echo ""

# ── 生成 alias ───────────────────────────────────────────────────────────────

if [[ "$DEE_MODE" == "box64" ]]; then
  RUNNER="\"$SCRIPT_DIR/scripts/run_dee_with_box64.sh\""
else
  RUNNER="\"$SCRIPT_DIR/scripts/run_dee_with_fex.sh\""
fi

ALIAS_BLOCK="
# dee-win aliases（由 setup.sh 生成）
source \"$ENV_FILE\"
alias dee=$RUNNER"

info "建议添加以下内容到 shell 配置文件："
echo ""
echo -e "${YELLOW}${ALIAS_BLOCK}${NC}"
echo ""

# 自动写入 shell profile
SHELL_PROFILE=""
if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_PROFILE="$HOME/.zshrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
  SHELL_PROFILE="$HOME/.bash_profile"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_PROFILE="$HOME/.bashrc"
fi

if [[ -n "$SHELL_PROFILE" ]]; then
  prompt "是否自动追加到 $SHELL_PROFILE？[y/N]: "
  read -r APPEND_CHOICE
  if [[ "${APPEND_CHOICE,,}" == "y" ]]; then
    if grep -q "dee-win aliases" "$SHELL_PROFILE" 2>/dev/null; then
      warn "检测到已存在 dee-win alias 块，跳过（如需更新请手动编辑 $SHELL_PROFILE）。"
    else
      printf '%s\n' "$ALIAS_BLOCK" >> "$SHELL_PROFILE"
      ok "已追加到 $SHELL_PROFILE"
      echo ""
      info "运行以下命令使其立即生效："
      echo -e "  ${BOLD}source $SHELL_PROFILE${NC}"
    fi
  else
    info "已跳过，可稍后手动粘贴。"
  fi
fi

echo ""
echo -e "${GREEN}${BOLD}配置完成！${NC}"
echo ""
echo "快速验证："
echo "  dee --help"
echo ""
