#!/usr/bin/env bash
# pdf-translate 论文双栏翻译封装脚本
# 用法: pdf-translate.sh <input.pdf> [输出目录] [页码] [lang-out]
#   input.pdf     输入论文 PDF
#   输出目录       默认 ./babeldoc-output-<文件名>
#   页码           默认全部，例 "1-10" 跳过参考文献
#   lang-out       默认 zh-CN
#
# 方案: pdf2zh-next + DeepSeek-V4-Flash-0731 + JSON mode (PCL 网关)
# 产出: *.zh-CN.dual.pdf（中英对照双栏）+ *.zh-CN.mono.pdf（纯中文）
set -euo pipefail

INPUT="${1:?用法: pdf-translate.sh <input.pdf> [输出目录] [页码] [lang-out]}"
OUTDIR="${2:-}"
PAGES="${3:-}"
LANG_OUT="${4:-zh-CN}"
LANG_IN="en"

# ---- 配置（按需修改）----
OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://llmapi.pcl.ac.cn/v1}"
OPENAI_MODEL="${OPENAI_MODEL:-DeepSeek-V4-Flash-0731}"
API_KEY="${XGR_ALL_API_KEY:-${OPENAI_API_KEY:-}}"

# ---- 检查 ----
command -v pdf2zh_next >/dev/null 2>&1 || {
    echo "ERROR: pdf2zh_next 未安装"
    echo "  安装: uv tool install --python 3.12 pdf2zh-next"
    echo "  再 pin: VIRTUAL_ENV=~/.local/share/uv/tools/pdf2zh-next uv pip install 'bitstring<5'"
    exit 1
}
[ -z "$API_KEY" ] && { echo "ERROR: 未设置 API Key（XGR_ALL_API_KEY 或 OPENAI_API_KEY）"; exit 1; }
[ -f "$INPUT" ] || { echo "ERROR: 文件不存在: $INPUT"; exit 1; }

# 默认输出目录
STEM=$(basename "$INPUT" .pdf)
[ -z "$OUTDIR" ] && OUTDIR="$(dirname "$INPUT")/babeldoc-output-${STEM}"
mkdir -p "$OUTDIR"

# PCL 网关国内直连，勿走代理
unset ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy

PAGE_ARG=()
[ -n "$PAGES" ] && PAGE_ARG=(--pages "$PAGES")

echo "==> 翻译: $INPUT"
echo "    模型: $OPENAI_MODEL @ $OPENAI_BASE_URL"
echo "    方向: $LANG_IN -> $LANG_OUT"
echo "    页码: ${PAGES:-全部}"
echo "    输出: $OUTDIR"
echo

pdf2zh_next "$INPUT" \
  --lang-in "$LANG_IN" --lang-out "$LANG_OUT" \
  --openai \
  --openai-model "$OPENAI_MODEL" \
  --openai-base-url "$OPENAI_BASE_URL" \
  --openai-api-key "$API_KEY" \
  --openai-enable-json-mode \
  --qps 8 \
  --output "$OUTDIR" \
  --ignore-cache \
  "${PAGE_ARG[@]}" 2>&1 | tee "$OUTDIR/translate.log"

echo
echo "==> 质量验证..."

# 找到 babeldoc venv 的 python（pdf2zh-next 依赖 babeldoc）
VENV=""
for candidate in \
    "$HOME/.local/share/uv/tools/babeldoc" \
    "$HOME/.local/share/uv/tools/pdf2zh-next"; do
    if [ -x "$candidate/bin/python" ] && "$candidate/bin/python" -c "import pymupdf" 2>/dev/null; then
        VENV="$candidate/bin/python"; break
    fi
done

if [ -z "$VENV" ]; then
    echo "  (跳过质量验证：pymupdf 不可用)"
else
    "$VENV" - "$OUTDIR" <<'PYEOF'
import pymupdf, re, os, sys
outdir = sys.argv[1]
monos = [f for f in os.listdir(outdir) if f.endswith('.mono.pdf')]
if not monos:
    print("  (未找到 mono.pdf，跳过)"); sys.exit(0)
d = pymupdf.open(os.path.join(outdir, monos[0]))
total_cjk = 0; body_untrans = 0
for page in d:
    txt = page.get_text()
    total_cjk += len(re.findall(r'[\u4e00-\u9fff]', txt))
    for run in re.findall(r'(?:[A-Za-z][A-Za-z ,\.\-:/\(\)]{60,})', txt):
        if re.search(r'[\u4e00-\u9fff]', run): continue
        low = run.lower()
        if re.search(r'\bet al\b|\bproc\.|\bvol\.|"[^"]+"|,\s*\d{4}\b', low): continue
        if re.search(r'\b(the|is|are|we|this|that|with|for)\b', low): body_untrans += 1
print(f"  中文={total_cjk}  正文未翻={body_untrans}")
if body_untrans == 0:
    print("  ✅ 翻译完整，无正文残留")
elif body_untrans <= 5:
    print(f"  ℹ️ 轻微: {body_untrans} 段未翻译")
else:
    print(f"  ⚠️ 警告: {body_untrans} 段未翻译，可能需要补译")
PYEOF
fi

echo
echo "==> 产物："
ls -lh "$OUTDIR"/*.pdf 2>/dev/null
echo
echo "双栏对照版: ${OUTDIR}/${STEM}.zh-CN.dual.pdf"
