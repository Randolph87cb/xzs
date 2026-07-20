# CSP-J/S 第一轮客观题

本目录保存从洛谷有题 `https://ti.luogu.com.cn/` 提取的 CSP-J1 / CSP-S1 第一轮客观题资料，范围为 2019-2025 年。

## 目录结构

- `CSP-J/YYYY-CSP-J1.md`：入门级第一轮 Markdown。
- `CSP-S/YYYY-CSP-S1.md`：提高级第一轮 Markdown。
- `raw/YYYY-CSP-J1.json`、`raw/YYYY-CSP-S1.json`：按试卷拆分的结构化原始结果。
- `raw/all.json`：合并后的题目结构。
- `status.json`：最近一次抽取状态、失败项和警告。

Markdown 尽量兼容 GESP 客观题导入风格：使用 `## 第 N 题`、`A.` / `B.` 选项和 `答案：X`。阅读程序、完善程序等复合大题会被展开为可入库的小题，并保留原始大题上下文。

## 数据库导入格式

CSP Markdown 的题面展示内容只保留题干、选项、答案和解析，不再把洛谷有题来源行写入每个题块。题目来源、试卷、原题序号和洛谷题目 ID 保留在 `raw/*.json`、`raw/all.json` 和导入内容 JSON 的元数据字段中。

每个题块应满足：

```markdown
## 第 N 题

题干 Markdown

A. 选项 A

B. 选项 B

答案：A

解析：Markdown 解析正文
```

复合大题会展开为小题。导入脚本按 raw 元数据映射题型：

- `single` -> `question_type = 1`，单选题。
- `multiselect` -> `question_type = 2`，多选/不定项选择题，答案按系统约定写为逗号分隔，例如 `A,C`。
- `truefalse` -> `question_type = 3`，判断题，选项为 `A. 正确`、`B. 错误`。

导入元数据字段：

- `import_batch = CSP_OBJECTIVE_MD`
- `import_source = CSP-J/YYYY-CSP-J1.md` 或 `CSP-S/YYYY-CSP-S1.md`
- `import_question_order = 展开后题号`
- `question_code = CSP-YYYY-J1-001` 或 `CSP-YYYY-S1-001`

当前状态：`raw/all.json` 中 600 题均已有答案、解析和导入元数据，解析已写回 Markdown 与 raw JSON；`import-csp-objective-questions.ps1` 当前可导入 600 题。默认导入脚本仍会阻止解析为空或 `暂无解析` 的题写入可导入 SQL。

整理与校验命令：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\prepare-csp-objective-questions.ps1 -NormalizeFromRaw
powershell -ExecutionPolicy Bypass -File .\scripts\prepare-csp-objective-questions.ps1 -QualityCheck
powershell -ExecutionPolicy Bypass -File .\scripts\import-csp-objective-questions.ps1 -DryRun
```

解析生成流程：

```powershell
# 仅生成 prompt/request 到 .tmp，不调用外部 API
powershell -ExecutionPolicy Bypass -File .\scripts\generate-csp-question-analysis.ps1 -PromptOnly -Years 2019 -Groups J -MaxQuestions 5

# 使用 OpenAI-compatible chat/completions API 生成结果
# 默认从环境变量或 .env 读取 MICUAPI_BASE_URL、MICUAPI_API_KEY；不会输出或写入 key 值
powershell -ExecutionPolicy Bypass -File .\scripts\generate-csp-question-analysis.ps1 -InvokeApi -Years 2019 -Groups J -MaxQuestions 5

# 如服务路径不是 /v1/chat/completions，可覆盖 endpoint path
powershell -ExecutionPolicy Bypass -File .\scripts\generate-csp-question-analysis.ps1 -InvokeApi -ApiEndpointPath /chat/completions -Years 2019 -Groups J -MaxQuestions 5

# 将 .tmp/csp-question-analysis/results 中通过质量检查的结果合并回 raw JSON 和 Markdown
powershell -ExecutionPolicy Bypass -File .\scripts\generate-csp-question-analysis.ps1 -MergeResults

# 检查解析缺口和已生成结果数量
powershell -ExecutionPolicy Bypass -File .\scripts\generate-csp-question-analysis.ps1 -QualityCheck
```

`.tmp/csp-question-analysis` 是解析生成的可复跑、可审计临时工作区，包含 prompt/request/result 等过程产物，不提交到仓库。

生成导入 SQL：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-csp-objective-questions.ps1 -SqlOnly
```

## 主流程：控制当前已登录浏览器

1. 人工确认 Edge 或浏览器已登录洛谷有题，例如能访问 `https://ti.luogu.com.cn/problemset/1035`，页面标题类似 `1035 - CSP 2020 提高级第一轮`。
2. 通过 Codex 浏览器控制工具或 Playwright 连接当前浏览器会话，进入题库页面。
3. 脚本默认优先读取页面中的 `window._feInjection` 结构化数据；需要模拟人工页面流程时可使用 `--source-mode dom`，按“逐题点击题号 -> 点击显示答案与解析 -> 从可见文本提取题干、选项、正确答案”的方式提取。

可复用命令示例：

```powershell
node .\scripts\extract-luogu-youti-csp.js --cdp-url http://127.0.0.1:9222 --years 2019-2025 --groups J,S
```

如果当前浏览器不是通过远程调试端口启动，普通 Playwright 脚本不能直接附着到已打开窗口；此时可继续使用 Codex 浏览器控制工具完成页面验证，或切换到下面的备选流程。

## 备选流程：browser-session-manager

当无法直接控制当前 Edge 时，脚本会尝试读取 browser-session-manager 会话：

- `site=luogu-youti`
- `env=prod`
- `account=default`
- `browser=msedge`

刷新或创建登录态：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\browser-session-manager\scripts\refresh_login.ps1" `
  -Site luogu-youti `
  -Env prod `
  -Account default `
  -Browser msedge `
  -BaseUrl https://ti.luogu.com.cn/ `
  -CheckUrl https://ti.luogu.com.cn/problemset/1035
```

然后运行：

```powershell
node .\scripts\extract-luogu-youti-csp.js --years 2019-2025 --groups J,S
```

调试或公开页面验证时，可显式允许无登录的临时 Edge：

```powershell
node .\scripts\extract-luogu-youti-csp.js --allow-public-fallback --limit-sets 1 --limit-questions 3
```

## 验证建议

- 先运行帮助或 dry-run，确认命令不会输出 cookie、token、密码或 storageState 内容：

```powershell
node .\scripts\extract-luogu-youti-csp.js --help
node .\scripts\extract-luogu-youti-csp.js --dry-run --allow-public-fallback --limit-sets 1
```

- 抽取后检查 `status.json` 中 `failures` 是否为空。
- 抽样核对数学公式、图片题和阅读程序题。DOM 可访问文本中数学公式可能出现空格增多、结构丢失或换行异常；结构化注入数据通常更完整，但仍需人工抽样。
- 检查生成文件不包含敏感字段：

```powershell
Select-String -Path .\docs\question-bank\CSP\**\*.md,.\docs\question-bank\CSP\**\*.json -Pattern 'cookie|token|password|authorization|localStorage' -CaseSensitive:$false
```

## 已知限制

- 洛谷有题的阅读程序和完善程序常以一个大题包含多个作答小题。脚本会展开为小题，但为了保留上下文，Markdown 中可能重复出现大题材料。
- `--source-mode dom` 依赖页面当前文案和可见文本，公式质量不如 `window._feInjection`。
- 脚本不会保存任何 cookie、token、账号密码或完整登录态文件到仓库。
