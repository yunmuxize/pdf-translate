---
name: pdf-translate
description: Translate academic PDFs to bilingual dual-column layout using pdf2zh-next + DeepSeek-V4-Flash. Use when the user asks to translate a paper/PDF to Chinese, says "翻译论文", "translate paper", "双栏翻译", "帮我翻译", or gives a PDF path for translation.
argument-hint: "[pdf-path] [page-range]"
allowed-tools: Bash(*), Read, Write
---

# PDF Bilingual Dual-Column Translation

Translate: $ARGUMENTS

## Role

Fast academic PDF translation producing a **bilingual dual-column PDF** (left: original English, right: Chinese). Powered by pdf2zh-next (BabelDOC orchestration layer) + DeepSeek-V4-Flash-0731 + JSON mode via PCL gateway.

## Constants

- **PDF2ZH_NEXT** — `~/.local/bin/pdf2zh_next` (installed via `uv tool install --python 3.12 pdf2zh-next`, requires `bitstring<5` pin)
- **VENV** — `~/.local/share/uv/tools/babeldoc` (for pymupdf quality verification)
- **GATEWAY** — `https://llmapi.pcl.ac.cn/v1` (PCL, 国内直连，**勿走代理**)
- **MODEL** — `DeepSeek-V4-Flash-0731` (3s/段，无 reasoning；GLM-5.2 慢 5 倍因强制 reasoning 不可关闭)
- **API_KEY** — `$XGR_ALL_API_KEY` environment variable
- **JSON_MODE** — `--openai-enable-json-mode` 强制结构化输出，避免解析错误
- **WRAPPER** — `~/Paper/babeldoc-translate.sh`（封装脚本）

## Setup Check

Before first use each session, verify:
```bash
command -v pdf2zh_next >/dev/null && echo "OK" || echo "MISSING: uv tool install --python 3.12 pdf2zh-next"
[ -n "$XGR_ALL_API_KEY" ] && echo "KEY OK" || echo "MISSING: XGR_ALL_API_KEY"
```

If `bitstring` import fails (cannot import name 'BitStream'), pin it:
```bash
VIRTUAL_ENV=~/.local/share/uv/tools/pdf2zh-next uv pip install 'bitstring<5'
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
