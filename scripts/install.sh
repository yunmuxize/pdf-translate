#!/usr/bin/env bash
# pdf-translate 一键安装脚本
# 用法: bash install.sh
set -euo pipefail

echo "=========================================="
echo "  pdf-translate 安装程序"
echo "=========================================="

# ---- 检查依赖 ----
echo ""
echo "[1/6] 检查依赖..."

if ! command -v uv >/dev/null 2>&1; then
    echo "  ✗ uv 未安装。请先安装 uv："
    echo "    curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi
echo "  ✓ uv: $(uv --version)"

if [ -z "${XGR_ALL_API_KEY:-}" ]; then
    echo "  ⚠ XGR_ALL_API_KEY 未设置（PCL 网关 API Key）"
    echo "    安装后使用前需要设置：export XGR_ALL_API_KEY=your-key"
    echo "    或修改脚本中的 API_KEY 指向你的 OpenAI 兼容端点"
else
    echo "  ✓ XGR_ALL_API_KEY 已设置"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---- 安装 pdf2zh-next ----
echo ""
echo "[2/6] 安装 pdf2zh-next..."
if command -v pdf2zh_next >/dev/null 2>&1; then
    echo "  ✓ pdf2zh_next 已安装: $(which pdf2zh_next)"
else
    uv tool install --python 3.12 pdf2zh-next
    echo "  ✓ pdf2zh-next 安装完成"
fi

# ---- 修复 bitstring 兼容性 ----
echo ""
echo "[3/6] 修复 bitstring 兼容性..."
VENV="${HOME}/.local/share/uv/tools/pdf2zh-next"
if [ -d "$VENV" ]; then
    if ! "$VENV/bin/python" -c "from bitstring import BitStream" 2>/dev/null; then
        VIRTUAL_ENV="$VENV" uv pip install 'bitstring<5' 2>/dev/null
        echo "  ✓ bitstring 已 pin 到 <5"
    else
        echo "  ✓ bitstring 兼容性 OK"
    fi
else
    echo "  ⚠ pdf2zh-next venv 未找到，跳过 bitstring 检查"
fi

# ---- 预热资产 ----
echo ""
echo "[4/6] 预下载 BabelDOC 资产（字体/模型，约 200MB）..."
if command -v babeldoc >/dev/null 2>&1; then
    echo "  babeldoc 已安装，尝试预热..."
    # 不设代理，modelscope 国内直连
    unset ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy
    timeout 120 babeldoc --warmup 2>&1 | tail -3 && echo "  ✓ 资产预热完成" || echo "  ⚠ 预热未完成（可稍后手动运行 babeldoc --warmup）"
else
    echo "  ⚠ babeldoc CLI 未找到（pdf2zh-next 内部会按需下载，首次翻译会稍慢）"
fi

# ---- 安装 skill ----
echo ""
echo "[5/6] 安装 OpenCode skill..."
SKILL_DIR="${HOME}/.config/opencode/skills/pdf-translate"
if [ -d "${HOME}/.config/opencode/skills" ]; then
    mkdir -p "$SKILL_DIR"
    cp "$SCRIPT_DIR/../skill/SKILL.md" "$SKILL_DIR/SKILL.md"
    echo "  ✓ skill 已安装到 $SKILL_DIR"
else
    echo "  ⚠ OpenCode skills 目录不存在（~/.config/opencode/skills/），跳过 skill 安装"
    echo "    如需使用 OpenCode skill，请先安装 OpenCode"
fi

# ---- 安装封装脚本 ----
echo ""
echo "[6/6] 安装翻译脚本..."
cp "$SCRIPT_DIR/pdf-translate.sh" "${HOME}/pdf-translate.sh"
chmod +x "${HOME}/pdf-translate.sh"
echo "  ✓ 脚本已安装到 ~/pdf-translate.sh"

# ---- 完成 ----
echo ""
echo "=========================================="
echo "  安装完成！"
echo "=========================================="
echo ""
echo "使用方式："
echo "  OpenCode: 直接说「帮我翻译 xxx.pdf」"
echo "  命令行:   bash ~/pdf-translate.sh paper.pdf"
echo ""
echo "确保 XGR_ALL_API_KEY 已设置后即可使用。"
