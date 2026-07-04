# 前端覆盖式重构阶段 3 Question Renderer 报告

## 阶段范围

阶段 3 的目标是把题目渲染能力从业务页面剥离为独立包，用单元测试锁定 Markdown、历史 HTML、KaTeX、代码高亮、XSS 清理和缓存行为。阶段 3 不迁移学生端答题页。

- 日期：2026-07-04
- 基于提交：`b9a411e5`
- 包：`frontend/packages/question-renderer`

## 已落地内容

新增包：

```text
frontend/packages/question-renderer/
  package.json
  vitest.config.ts
  src/
    QuestionMarkdown.vue
    index.ts
    markdown-it-texmath.d.ts
    render.test.ts
    render.ts
```

导出能力：

- `renderQuestionContent`
- `clearQuestionRenderCache`
- `getQuestionRenderCacheSize`
- `QuestionMarkdown`
- `QuestionStem`
- `QuestionOption`
- `QuestionAnalysis`

渲染能力：

- Markdown 基础渲染。
- 历史 HTML 片段渲染。
- HTML 文本节点里的 `$...$` 行内公式。
- `$$...$$` 块级公式。
- KaTeX 渲染。
- 指定语言代码高亮。
- DOMPurify 安全清理。
- 相同内容渲染缓存。

代码高亮已注册语言：

- `bash`、`shell`、`sh`
- `cpp`、`c++`
- `csharp`、`cs`
- `css`
- `java`
- `javascript`、`js`
- `json`
- `markdown`、`md`
- `python`、`py`
- `sql`
- `typescript`、`ts`
- `xml`、`html`

## 与旧实现的关键差异

旧 Vue 2 `MarkdownView` 对无语言代码块会尝试 `highlightAuto`。新包刻意不做自动语言猜测，只做 HTML escape。

原因：

- 自动语言猜测会在大试卷上造成不稳定 CPU 消耗。
- 代码块中的 `$N$` 必须保持字面量，不能被公式渲染干扰。
- 后续应通过题库编辑器显式保存代码语言，而不是在展示阶段猜测。

## 单元测试

命令：

```powershell
pnpm --filter @xzs/question-renderer test
```

结果：

| 指标 | 结果 |
| --- | ---: |
| Test Files | `1 passed` |
| Tests | `9 passed` |
| Duration | `2.74s` |

覆盖点：

- HTML 包裹行内公式 `$N$`。
- 纯 Markdown 行内公式 `$N$`。
- HTML 包裹块级公式。
- `<pre><code>` 中的 `$N$` 不渲染公式。
- 行内 `<code>$N$</code>` 不渲染公式，外部 `$X$` 正常渲染。
- HTML 属性中的 `$N$` 不注入 KaTeX。
- `<script>`、`onerror`、`javascript:` 被清理。
- 无语言代码块不触发 `highlightAuto`。
- 相同内容缓存命中。

## 学生端构建验证

命令：

```powershell
.\frontend\scripts\build-student.ps1
```

结果：通过。

构建输出：

| 文件 | 体积 |
| --- | ---: |
| `student/index.html` | `1.06 kB`, gzip `0.61 kB` |
| CSS | `359.64 kB`, gzip `48.51 kB` |
| JS | `1043.10 kB`, gzip `340.61 kB` |

## 依赖处理

阶段 3 新增依赖：

- `dompurify`
- `highlight.js`
- `katex`
- `markdown-it`
- `markdown-it-texmath`
- `vitest`
- `jsdom`

安装时遇到 `jsdom@27.3.1` 不存在的问题，已改为 npm 当前可安装版本 `29.1.1`。同时把 `vitest` 调整到 `4.1.9`，`dompurify` 调整到 `3.4.11`。

## 已知问题

- 还没有把学生端答题页切到 `@xzs/question-renderer`。
- `QuestionStem`、`QuestionOption`、`QuestionAnalysis` 当前复用 `QuestionMarkdown` 导出，后续迁业务时可以按样式差异拆成独立组件。
- 真实题库样本 Q01-Q10 尚未接入自动化数据库/接口回归。
- Vite/Rolldown 的 `@vueuse/core` 第三方注释告警仍存在，来自学生端 Element Plus 依赖链，不影响 renderer 测试。

## 阶段 3 验收结论

阶段 3 的独立题目渲染包已可用，且用单元测试覆盖了此前 `$N$` 未渲染、代码块误渲染、HTML 属性误处理和 XSS 清理等关键风险。后续阶段 4 可以把学生端答题页迁移到该包。
