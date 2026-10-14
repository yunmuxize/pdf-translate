---
name: pdf-translate
description: Translate academic PDFs to bilingual dual-column layout + extract figures for notes. Use when the user asks to translate a paper/PDF to Chinese, says "翻译论文", "translate paper", "双栏翻译", "帮我翻译", "提取图片", "论文笔记", "整理论文", or gives a PDF path for translation/analysis.
argument-hint: "[pdf-path] [page-range] [--notes]"
allowed-tools: Bash(*), Read, Write
---

# PDF Translation + Figure Extraction + Notes

Translate: $ARGUMENTS

## Role

Academic PDF toolkit with three capabilities:
1. **翻译** — bilingual dual-column PDF (pdf2zh-next + DeepSeek-V4-Flash + JSON mode)
2. **图片提取** — extract all figures from PDF with page/bbox metadata (MinerU + PyMuPDF fallback)
3. **笔记生成** — generate illustrated study notes skeleton with embedded paper figures

## Constants

- **PDF2ZH_NEXT** — `~/.local/bin/pdf2zh_next` (installed via `uv tool install --python 3.12 pdf2zh-next`, requires `bitstring<5` pin)
- **MINERU** — `~/.mineru/bin/mineru` (installed via `uv venv ~/.mineru --python 3.12 && VIRTUAL_ENV=~/.mineru uv pip install "mineru[all]"`, set `MINERU_MODEL_SOURCE=modelscope` for domestic download)
- **VENV** — `~/.local/share/uv/tools/babeldoc` (for pymupdf quality verification + fallback image extraction)
- **GATEWAY** — `https://llmapi.pcl.ac.cn/v1` (PCL, 国内直连，**勿走代理**)
- **MODEL** — `DeepSeek-V4-Flash-0731` (3s/段，无 reasoning；GLM-5.2 慢 5 倍因强制 reasoning 不可关闭)
- **API_KEY** — `$XGR_ALL_API_KEY` environment variable
- **JSON_MODE** — `--openai-enable-json-mode` 强制结构化输出，避免解析错误
- **WRAPPER** — `~/Paper/babeldoc-translate.sh`（翻译封装脚本）
- **NOTES_SCRIPT** — `~/Paper/paper-notes.sh`（图片提取+笔记生成脚本）

## Setup Check

Before first use each session, verify:
```bash
command -v pdf2zh_next >/dev/null && echo "pdf2zh OK" || echo "MISSING: uv tool install --python 3.12 pdf2zh-next"
[ -x ~/.mineru/bin/mineru ] && echo "mineru OK" || echo "MISSING: see install.sh for MinerU"
[ -n "$XGR_ALL_API_KEY" ] && echo "KEY OK" || echo "MISSING: XGR_ALL_API_KEY"
```

If `bitstring` import fails (cannot import name 'BitStream'), pin it:
```bash
VIRTUAL_ENV=~/.local/share/uv/tools/pdf2zh-next uv pip install 'bitstring<5'
```

## MinerU Installation (if missing)

```bash
uv venv ~/.mineru --python 3.12
VIRTUAL_ENV=~/.mineru uv pip install -U "mineru[all]"
# 国内模型下载加速：
export MINERU_MODEL_SOURCE=modelscope
```

## Workflow

### Step 1: Parse Arguments

From `$ARGUMENTS`, extract:
- **PDF path** (required) — absolute or relative path to the PDF file
- **Page range** (optional) — e.g. "1-10" to translate only pages 1-10 (skip references)
- If user says "参考文献也要翻" or "全文", translate all pages (no --pages flag)
- If user says "只翻正文" or "不要翻参考文献", find where References start and use `--pages 1-N`

### Step 2: Verify Input

```bash
[ -f "$PDF" ] || { echo "ERROR: 文件不存在: $PDF"; exit 1; }
```

Check page count and find References page if needed:
```bash
~/.local/share/uv/tools/babeldoc/bin/python -c "
import pymupdf
d=pymupdf.open('$PDF')
print('pages:', d.page_count)
for i,page in enumerate(d):
    if 'References' in page.get_text() or 'REFERENCES' in page.get_text():
        print(f'References start at page {i+1}'); break
"
```

### Step 3: Translate

**Critical: unset all proxy env vars (PCL gateway is domestic, proxy causes timeout).**

```bash
unset ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy
OUTDIR="$(dirname "$PDF")/babeldoc-output-$(basename "$PDF" .pdf)"
mkdir -p "$OUTDIR"

pdf2zh_next "$PDF" \
  --lang-in en --lang-out zh-CN \
  --openai \
  --openai-model "DeepSeek-V4-Flash-0731" \
  --openai-base-url "https://llmapi.pcl.ac.cn/v1" \
  --openai-api-key "$XGR_ALL_API_KEY" \
  --openai-enable-json-mode \
  --qps 8 \
  --output "$OUTDIR" \
  $PAGES_ARG \
  2>&1 | tee "$OUTDIR/translate.log"
```

- Use `--pages "1-N"` only if user wants to skip references
- Use `--ignore-cache` only if user asks to re-translate
- Default `--qps 8` for speed (DeepSeek-Flash handles it fine)
- For incremental translation (e.g. first did p1-10, now want full), omit `--ignore-cache` to reuse cached pages

### Step 4: Verify Quality

```bash
~/.local/share/uv/tools/babeldoc/bin/python -c "
import pymupdf, re, os
mono=[f for f in os.listdir('$OUTDIR') if f.endswith('.mono.pdf')][0]
d=pymupdf.open(os.path.join('$OUTDIR',mono))
total_cjk=0; body_untrans=0
for page in d:
    txt=page.get_text()
    total_cjk+=len(re.findall(r'[\u4e00-\u9fff]',txt))
    for run in re.findall(r'(?:[A-Za-z][A-Za-z ,\.\-:/\(\)]{60,})',txt):
        if re.search(r'[\u4e00-\u9fff]',run): continue
        low=run.lower()
        if re.search(r'\bet al\b|\bproc\.|\bvol\.|\"[^\"]+\"|,\s*\d{4}\b', low): continue
        if re.search(r'\b(the|is|are|we|this|that|with|for)\b', low): body_untrans+=1
print(f'中文={total_cjk}  正文未翻={body_untrans}')
print('✅ 翻译完整' if body_untrans==0 else f'⚠️ {body_untrans} 段未翻')
"
```

### Step 5: Report Results

Report to user:
- Total time consumed
- Pages translated
- Quality check result (中文字符数 / 未翻段数)
- Output file paths:
  - `*.zh-CN.dual.pdf` — bilingual dual-column (primary deliverable)
  - `*.zh-CN.mono.pdf` — Chinese-only version

### Step 6: Figure Extraction (when user asks for notes/笔记/图片)

If user says "提取图片", "论文笔记", "写笔记", "整理归档", or wants illustrated notes:

**Option A: MinerU (preferred — captures vector figures + layout analysis)**

```bash
unset ALL_PROXY HTTPS_PROXY HTTP_PROXY all_proxy https_proxy http_proxy
export MINERU_MODEL_SOURCE=modelscope
MINERU=~/.mineru/bin/mineru
ANALYSIS_DIR="$(dirname "$PDF")/paper-analysis-$(basename "$PDF" .pdf)"

$MINERU -p "$PDF" -o "$ANALYSIS_DIR" -b hybrid-engine --effort high 2>&1 | tail -5
# Output: $ANALYSIS_DIR/images/ (all figures as PNG with page/bbox metadata)
#         $ANALYSIS_DIR/*.md (parsed markdown)
#         $ANALYSIS_DIR/*_middle.json (coordinates for each figure)
```

MinerU advantages over PyMuPDF:
- Captures vector figures (PyMuPDF only gets embedded raster images)
- Identifies figure/table/chart/equation blocks with type labels
- Pairs image_body with image_caption (knows which caption belongs to which figure)
- Correctly handles dual-column layout reading order

Image naming: `images/page_{N}_{type}_{idx}.png` (e.g. `page_2_image_1.png`, `page_3_chart_1.png`)

**Option B: PyMuPDF fallback (fast, no model download, but misses vector figures)**

```bash
~/.local/share/uv/tools/babeldoc/bin/python - "$PDF" "$IMGDIR" <<'PYEOF'
import pymupdf, os, json, sys
pdf, imgdir = sys.argv[1], sys.argv[2]
doc = pymupdf.open(pdf)
os.makedirs(imgdir, exist_ok=True)
img_info = []
for page_num in range(len(doc)):
    page = doc[page_num]
    # Extract embedded images (raster only)
    for img_idx, img in enumerate(page.get_images(full=True)):
        xref = img[0]
        pix = pymupdf.Pixmap(doc, xref)
        if pix.n - pix.alpha > 3: pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
        if pix.width > 300 and pix.height > 200:
            fname = f"p{page_num+1:02d}_img{img_idx+1}.png"
            pix.save(os.path.join(imgdir, fname))
            img_info.append({"file": fname, "page": page_num+1, "w": pix.width, "h": pix.height})
        pix = None
    # Also render full page (captures vector figures)
    mat = pymupdf.Matrix(3, 3)  # 216 DPI
    pix = page.get_pixmap(matrix=mat)
    pix.save(os.path.join(imgdir, f"page_{page_num+1:02d}_full.png"))
json.dump(img_info, open(os.path.join(imgdir, "images_meta.json"), "w"), ensure_ascii=False, indent=2)
print(f"Extracted {len(img_info)} embedded images + {len(doc)} full-page renders")
PYEOF
```

**Step 6b: Generate notes skeleton with embedded figures**

Use `~/Paper/paper-notes.sh --notes` or manually create a Markdown file with `![](images/xxx.png)` references at relevant sections. When writing notes, embed the extracted figures alongside the corresponding paper sections (e.g., Figure 2 framework diagram in the "Method Overview" section).

## Performance Reference

| Pages | Time | Notes |
|-------|------|-------|
| 10 pp | ~8 min | Body only (no references) |
| 31 pp | ~22 min | Full paper with references |

## Common Issues

| Issue | Fix |
|-------|-----|
| `bitstring BitStream ImportError` | `VIRTUAL_ENV=~/.local/share/uv/tools/pdf2zh-next uv pip install 'bitstring<5'` |
| Connection timeout to PCL | Ensure proxy env vars are unset (PCL is domestic) |
| `OpenAI API key is required` | Pass `--openai-api-key "$XGR_ALL_API_KEY"` explicitly |
| Slow (15s/段) | Wrong model — must use `DeepSeek-V4-Flash-0731`, NOT `GLM-5.2` (has forced reasoning) |
| JSON parse errors | Ensure `--openai-enable-json-mode` is set |
| Stuck at 10/13 for hours | Using raw `babeldoc` CLI instead of `pdf2zh_next` — switch to pdf2zh_next |

## Do NOT

- Do NOT use raw `babeldoc` CLI (tenacity retry gets stuck on failed paragraphs)
- Do NOT use `GLM-5.2` (forced reasoning, 5x slower, `thinking:disabled` ignored by PCL gateway)
- Do NOT use `DeepSeek-V4-Pro` (unstable JSON on long text, also gets stuck)
- Do NOT set proxy env vars (`llmapi.pcl.ac.cn` is domestic; proxy causes timeout)
- Do NOT manually patch translations with pymupdf — fix the tool config instead
