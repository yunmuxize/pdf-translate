#!/usr/bin/env bash
# paper-notes.sh — 论文精读笔记生成工具
# 结合 MinerU（图片提取+版面分析）+ BabelDOC（翻译）生成图文并茂的学习笔记
#
# 用法: paper-notes.sh <input.pdf> [--translate] [--notes]
#   input.pdf     输入论文 PDF
#   --translate   同时生成中文双栏翻译（默认仅提取图片+解析）
#   --notes       生成笔记骨架 Markdown（含图片引用）
#
# 依赖:
#   - MinerU: ~/.mineru/bin/mineru（图片提取+版面分析）
#   - pdf2zh-next: ~/.local/bin/pdf2zh_next（翻译，可选）
#   - PyMuPDF: babeldoc venv（质量验证+备用图片提取）
set -euo pipefail

INPUT="${1:?用法: paper-notes.sh <input.pdf> [--translate] [--notes]}"
shift || true

DO_TRANSLATE=false
DO_NOTES=false
for arg in "$@"; do
    case "$arg" in
        --translate) DO_TRANSLATE=true ;;
        --notes) DO_NOTES=true ;;
    esac
done

[ -f "$INPUT" ] || { echo "ERROR: 文件不存在: $INPUT"; exit 1; }

STEM=$(basename "$INPUT" .pdf)
OUTDIR="$(dirname "$INPUT")/paper-analysis-${STEM}"
IMGDIR="${OUTDIR}/images"
mkdir -p "$IMGDIR"

# ---- 路径常量 ----
MINERU="${HOME}/.mineru/bin/mineru"
BABELDOC_VENV="${HOME}/.local/share/uv/tools/babeldoc/bin/python"

echo "==> 论文分析: $INPUT"
echo "    输出: $OUTDIR"
echo

# ---- Step 1: MinerU 图片提取 + 版面分析 ----
echo "==> [1/3] MinerU 图片提取 + 版面分析..."
if [ -x "$MINERU" ]; then
    # 国内直连 modelscope 拉模型，勿走代理
    unset ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy
    export MINERU_MODEL_SOURCE=modelscope
    
    "$MINERU" -p "$INPUT" -o "$OUTDIR" -b hybrid-engine --effort high 2>&1 | tail -5
    echo "  ✓ MinerU 解析完成"
    echo "  图片: $(ls "$IMGDIR"/*.png 2>/dev/null | wc -l) 张"
    echo "  Markdown: ${OUTDIR}/${STEM}.md"
else
    echo "  ⚠ MinerU 未安装，使用 PyMuPDF 备用方案提取图片"
    "$BABELDOC_VENV" - "$INPUT" "$IMGDIR" <<'PYEOF'
import pymupdf, os, json, sys
pdf, imgdir = sys.argv[1], sys.argv[2]
doc = pymupdf.open(pdf)
img_info = []
for page_num in range(len(doc)):
    page = doc[page_num]
    # 提取嵌入图片
    for img_idx, img in enumerate(page.get_images(full=True)):
        xref = img[0]
        pix = pymupdf.Pixmap(doc, xref)
        if pix.n - pix.alpha > 3:
            pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
        if pix.width > 300 and pix.height > 200:  # 过滤小图标
            fname = f"p{page_num+1:02d}_img{img_idx+1}.png"
            pix.save(os.path.join(imgdir, fname))
            img_info.append({"file": fname, "page": page_num+1, "w": pix.width, "h": pix.height})
        pix = None
    # 渲染整页（捕获矢量图）
    mat = pymupdf.Matrix(3, 3)
    pix = page.get_pixmap(matrix=mat)
    pix.save(os.path.join(imgdir, f"page_{page_num+1:02d}_full.png"))
json.dump(img_info, open(os.path.join(imgdir, "images_meta.json"), "w"), ensure_ascii=False, indent=2)
print(f"  PyMuPDF: {len(img_info)} 张嵌入图 + {len(doc)} 张整页渲染")
PYEOF
fi

# ---- Step 2: 翻译（可选）----
if [ "$DO_TRANSLATE" = true ]; then
    echo
    echo "==> [2/3] 中文双栏翻译..."
    unset ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy
    TRANS_DIR="$(dirname "$INPUT")/zh-translation"
    mkdir -p "$TRANS_DIR"
    
    if command -v pdf2zh_next >/dev/null 2>&1 && [ -n "${XGR_ALL_API_KEY:-}" ]; then
        pdf2zh_next "$INPUT" \
            --lang-in en --lang-out zh-CN \
            --openai --openai-model "DeepSeek-V4-Flash-0731" \
            --openai-base-url "https://llmapi.pcl.ac.cn/v1" \
            --openai-api-key "$XGR_ALL_API_KEY" \
            --openai-enable-json-mode --qps 8 \
            --output "$TRANS_DIR" 2>&1 | tail -3
        echo "  ✓ 翻译完成: $TRANS_DIR"
    else
        echo "  ⚠ pdf2zh_next 或 XGR_ALL_API_KEY 未配置，跳过翻译"
    fi
fi

# ---- Step 3: 生成笔记骨架（可选）----
if [ "$DO_NOTES" = true ]; then
    echo
    echo "==> [3/3] 生成笔记骨架..."
    NOTES_FILE="$(dirname "$INPUT")/${STEM}_学习笔记.md"
    
    # 收集图片列表
    IMAGES=$(ls "$IMGDIR"/*.png 2>/dev/null | head -20)
    
    cat > "$NOTES_FILE" << NOTESEOF
# ${STEM} 精读学习笔记

> **论文**: ${STEM}
> **笔记生成时间**: $(date +%Y-%m-%d)
> **图片目录**: \`images/\`

---

## 1. 论文整体预览

（在此填写整体概览...）

## 2. 核心方法

### Figure 引用

NOTESEOF
    
    # 自动插入图片引用
    for img in $IMAGES; do
        imgname=$(basename "$img")
        echo "" >> "$NOTES_FILE"
        echo "![${imgname}](images/${imgname})" >> "$NOTES_FILE"
        echo "" >> "$NOTES_FILE"
    done
    
    cat >> "$NOTES_FILE" << 'NOTESEOF2'

## 3. 实验结果

## 4. 关键公式

## 5. 疑问与解答

> 在此记录学习过程中的疑问...

---

*由 paper-notes.sh 自动生成骨架，请手动补充内容。*
NOTESEOF2
    echo "  ✓ 笔记骨架: $NOTES_FILE"
fi

echo
echo "==> 完成！"
echo "  图片: $IMGDIR"
[ -f "${OUTDIR}/${STEM}.md" ] && echo "  解析: ${OUTDIR}/${STEM}.md"
[ -f "$NOTES_FILE" ] && echo "  笔记: $NOTES_FILE"
ls -lh "$IMGDIR"/*.png 2>/dev/null | head -10
