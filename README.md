# pdf-translate — 论文双栏翻译 + 图片提取 Skill

一键将英文学术 PDF 翻译为**中英对照双栏 PDF**，并提取论文图片用于制作图文并茂的学习笔记。基于 [pdf2zh-next](https://github.com/PDFMathTranslate-next/PDFMathTranslate-next)（BabelDOC 编排层）+ DeepSeek-V4-Flash + JSON mode + [MinerU](https://github.com/opendatalab/MinerU)（图片提取与版面分析），通过 PCL 网关调用，国内直连无需代理。

## 功能

1. **翻译** — 中英对照双栏 PDF（`*.zh-CN.dual.pdf`）+ 纯中文版（`*.zh-CN.mono.pdf`）
2. **图片提取** — 从论文中提取所有 Figure 为 PNG，保留页码和坐标元数据
3. **笔记生成** — 生成带图片引用的 Markdown 笔记骨架

## 效果

| 指标 | 值 |
|---|---|
| 翻译速度 | 9 页正文 ≈ 6-8 分钟，31 页全文 ≈ 22 分钟 |
| 翻译质量 | 0 段漏翻（正文完整翻译） |
| 输出格式 | `*.zh-CN.dual.pdf`（中英对照双栏）+ `*.zh-CN.mono.pdf`（纯中文） |
| 参考文献 | 默认不翻译（可指定全文翻译） |

## 快速安装

```bash
git clone https://github.com/yunmuxize/pdf-translate.git
cd pdf-translate
bash scripts/install.sh
```

安装脚本会自动：
1. 用 `uv` 安装 `pdf2zh-next`（Python 3.12）
2. Pin `bitstring<5`（修复已知兼容问题）
3. 预下载 BabelDOC 资产（字体/模型，约 200MB）
4. 将 skill 安装到 `~/.config/opencode/skills/pdf-translate/`
5. 部署封装脚本到 `~/pdf-translate.sh`

## 前置要求

- **[uv](https://github.com/astral-sh/uv)** 已安装并在 PATH 中
- **PCL 网关 API Key**：环境变量 `XGR_ALL_API_KEY`（[鹏城实验室 LLM API](https://llmapi.pcl.ac.cn)）
- **OpenCode**（可选，用于 skill 自动触发；脚本也可独立使用）

如果你用其他 OpenAI 兼容网关，编辑 `scripts/pdf-translate.sh` 中的 `OPENAI_BASE_URL`、`OPENAI_MODEL`、`API_KEY` 即可。

## 使用方式

### 方式一：OpenCode Skill（推荐）

安装后，在 OpenCode 中直接说：
- "帮我翻译 xxx.pdf"
- "翻译这篇论文 /path/to/paper.pdf"
- "双栏翻译 xxx.pdf，只翻正文"
- "translate paper.pdf 1-10"

Skill 会自动触发，翻译完成后返回双栏 PDF 路径。

### 方式二：命令行脚本

```bash
# 翻译全文
bash ~/pdf-translate.sh paper.pdf

# 只翻 p1-10（跳过参考文献）
bash ~/pdf-translate.sh paper.pdf "" "1-10"

# 指定输出目录
bash ~/pdf-translate.sh paper.pdf ./output

# 翻译到其他语言
bash ~/pdf-translate.sh paper.pdf ./output "" ja
```

## 参数说明

| 参数 | 默认值 | 说明 |
|---|---|---|
| `input.pdf` | （必填） | 输入 PDF 路径 |
| `输出目录` | `./babeldoc-output-<stem>` | 输出目录 |
| `页码` | 全部 | 如 `1-10`、`1,3,5-8` |
| `lang-out` | `zh-CN` | 目标语言代码 |

## 技术方案

```
PDF → pdf2zh-next (BabelDOC 编排层)
         ├─ DocLayout-YOLO 版面分析（识别双栏/图表/公式）
         ├─ 段落切分 + 中间表示 (IR)
         ├─ DeepSeek-V4-Flash-0731 翻译（JSON mode，PCL 网关）
         ├─ 排版重排 + 字体映射
         └─ 输出 dual.pdf + mono.pdf
```

### 为什么选这个组合

| 尝试过的方案 | 问题 |
|---|---|
| 裸 babeldoc CLI + GLM-5.2 | GLM-5.2 JSON 输出错乱，289 段漏翻 |
| 裸 babeldoc CLI + DeepSeek-V4-Pro | 长文本 JSON 不稳定，卡在失败段落死循环 |
| babeldoc + GLM-5.2 + 手动补译 | 不成熟，pymupdf 叠加文本破坏排版 |
| **pdf2zh-next + DeepSeek-V4-Flash + JSON mode** | ✅ 0 段漏翻，速度快 |

关键发现：
- **GLM-5.2 慢 5 倍**：每段请求强制 reasoning（思考链），不可关闭，15s/段 vs Flash 的 3s/段
- **JSON mode 必须开**：`--openai-enable-json-mode` 强制 `response_format: json_object`，避免 LLM 输出格式错乱
- **pdf2zh-next 优于裸 babeldoc**：它是 BabelDOC 官方编排层，错误处理/限速更成熟，不会卡在失败段落
- **PCL 网关国内直连**：`llmapi.pcl.ac.cn` 勿走代理，代理反而超时

## 文件结构

```
pdf-translate/
├── README.md                  # 本文档
├── skill/
│   └── SKILL.md              # OpenCode skill 定义
├── scripts/
│   ├── install.sh            # 一键安装（含可选 MinerU）
│   ├── pdf-translate.sh      # 翻译封装脚本
│   └── paper-notes.sh        # 图片提取+笔记生成脚本
└── LICENSE
```

## 已知限制

- 扫描版 PDF（无文本层）无法翻译，需先 OCR
- 复杂表格内文字偶尔不翻译（DocLayout-YOLO 版面分析局限）
- 公式/图表保持原样不翻译（设计如此）
- 需要 PCL 网关或兼容的 OpenAI API 端点

## License

MIT
