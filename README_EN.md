# pdf-translate — Academic PDF Translation & Figure Extraction

**[中文说明](./README.md) | English**

A command-line toolkit and [OpenCode](https://opencode.ai/) skill for translating English academic papers into **bilingual (English–Chinese) PDFs**, extracting figures, and preparing illustrated Markdown study notes.

The translation pipeline uses [pdf2zh-next](https://github.com/PDFMathTranslate-next/PDFMathTranslate-next) and its BabelDOC-based layout processing, with the **DeepSeek-V4-Flash-0731** model through a configurable OpenAI-compatible API. The included scripts default to the [PCL LLM API gateway](https://llmapi.pcl.ac.cn). Figure extraction uses [MinerU](https://github.com/opendatalab/MinerU) when installed, or a PyMuPDF fallback.

## Features

- **Bilingual translation:** produce a side-by-side English/Chinese PDF (`*.zh-CN.dual.pdf`) and a Chinese-only PDF (`*.zh-CN.mono.pdf`).
- **Layout-aware processing:** preserve the overall paper layout, including columns, figures, and equations, through pdf2zh-next/BabelDOC.
- **Figure extraction:** use MinerU for document parsing and image extraction, or PyMuPDF to extract embedded images and render pages.
- **Study-note scaffolding:** generate a Markdown outline with image references.
- **Two ways to run:** an OpenCode skill or standalone shell scripts.

## Requirements

- [uv](https://github.com/astral-sh/uv), available on your `PATH`
- Python 3.12 (managed by `uv` during installation)
- Access to a compatible translation model API and an API key
- OpenCode (optional, for natural-language skill invocation)
- MinerU (optional, for enhanced figure and layout extraction)

The default configuration expects a PCL gateway key in `XGR_ALL_API_KEY`. You can use another OpenAI-compatible endpoint by setting `OPENAI_BASE_URL`, `OPENAI_MODEL`, and `OPENAI_API_KEY` instead.

## Quick Start

```bash
git clone https://github.com/yunmuxize/pdf-translate.git
cd pdf-translate
bash scripts/install.sh
```

The installer:

1. Installs `pdf2zh-next` using `uv` and Python 3.12.
2. Checks the `bitstring` compatibility issue and pins `bitstring<5` when necessary.
3. Attempts to warm up BabelDOC assets if the `babeldoc` command is available.
4. Copies the OpenCode skill to `~/.config/opencode/skills/pdf-translate/` **if that skills directory exists**.
5. Installs `~/pdf-translate.sh` and `~/paper-notes.sh`.
6. Optionally offers to install MinerU. Declining keeps the PyMuPDF fallback available, provided its environment is installed.

Set the API key before running a translation:

```bash
export XGR_ALL_API_KEY="your-api-key"
```

Alternatively, to use a different compatible API:

```bash
export OPENAI_BASE_URL="https://your-api-host.example/v1"
export OPENAI_MODEL="your-model"
export OPENAI_API_KEY="your-api-key"
```

> **Note:** The installer and translation scripts unset HTTP(S) proxy variables for their PCL/ModelScope-oriented workflow. If you use another gateway or network environment, inspect and adjust that behavior before running them.

## Usage

### Option 1: OpenCode skill

If you already have an OpenCode skills directory when running the installer, you can ask OpenCode to translate a PDF, for example:

- `Translate /path/to/paper.pdf into Chinese.`
- `Create a bilingual PDF for paper.pdf.`
- `Translate pages 1–10 of paper.pdf.`

The skill references the project's translation and paper-analysis workflows.

### Option 2: Command line

```bash
# Translate the entire document (including references)
bash ~/pdf-translate.sh paper.pdf

# Translate only pages 1–10
bash ~/pdf-translate.sh paper.pdf "" "1-10"

# Set the output directory
bash ~/pdf-translate.sh paper.pdf ./output

# Translate English into Japanese instead of Chinese
bash ~/pdf-translate.sh paper.pdf ./output "" ja
```

**Command syntax:**

```text
bash ~/pdf-translate.sh <input.pdf> [output-directory] [pages] [target-language]
```

| Argument | Default | Example |
| --- | --- | --- |
| `input.pdf` | Required | `paper.pdf` |
| Output directory | `babeldoc-output-<pdf-stem>` beside the input | `./output` |
| Pages | All pages | `1-10`, `1,3,5-8` |
| Target language | `zh-CN` | `ja` |

The script writes translation output and a `translate.log` file to the output directory. For Chinese output, the expected PDF names end in `.zh-CN.dual.pdf` and `.zh-CN.mono.pdf`. It also performs a best-effort check for untranslated English passages when PyMuPDF is available.

### Extract figures and generate notes

```bash
# Parse the paper and extract images
bash ~/paper-notes.sh paper.pdf

# Also create a Markdown study-note template
bash ~/paper-notes.sh paper.pdf --notes

# Include a translation step
bash ~/paper-notes.sh paper.pdf --translate --notes
```

MinerU is preferred for richer layout parsing. The fallback extracts embedded raster images and saves full-page renders, which can contain vector graphics but are **not** individually cropped figures.

## How Translation Works

```text
English academic PDF
       |
       v
pdf2zh-next / BabelDOC
  - Document layout analysis
  - Text extraction and segmentation
  - LLM translation via an OpenAI-compatible API (JSON mode)
  - Layout reconstruction and font handling
       |
       +--> Bilingual dual PDF
       +--> Translated mono PDF

Optional paper-notes workflow
  - MinerU parsing, or PyMuPDF fallback
  - Extracted images / page renders
  - Markdown note template
```

The translation wrapper enables JSON mode (`--openai-enable-json-mode`) and sets the model and gateway through environment variables. It defaults to DeepSeek-V4-Flash-0731 via PCL.

## Reported Results

The following numbers are **observations reported by the repository author**, not independently reproduced benchmarks or guarantees:

| Metric | Reported observation |
| --- | --- |
| Translation time for 9 body-text pages | Approximately 6–8 minutes |
| Translation time for 31 pages | Approximately 22 minutes |
| Untranslated body paragraphs in the author's test | 0 detected |
| Output | Bilingual dual PDF and translated mono PDF |

Results depend on the PDF layout, API latency, document length, and translation model.

## Project Structure

```text
pdf-translate/
├── README.md                 # Chinese documentation
├── README_EN.md              # English documentation
├── skill/
│   └── SKILL.md              # OpenCode skill instructions
├── scripts/
│   ├── install.sh            # Installer
│   ├── pdf-translate.sh      # Translation wrapper
│   └── paper-notes.sh        # Figure extraction and notes
└── LICENSE
```

## Known Limitations

- **Scanned PDFs** without a text layer require OCR before translation.
- **Complex tables** may contain text that the layout analysis does not translate.
- **Equations and text embedded in figures** are generally preserved rather than translated.
- An API key and access to a supported translation endpoint are required.
- Image extraction quality depends on whether MinerU or the fallback is used.
- The translation quality check is heuristic and does not prove semantic accuracy or full coverage.

## License

[MIT](./LICENSE)
