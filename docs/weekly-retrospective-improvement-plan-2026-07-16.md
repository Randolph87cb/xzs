# 周复盘修改计划（2026-07-16）

## 背景与现状

本次复盘按 Codex 对话所在文件夹归类。`D:\workspace\xzs` 最近一周主要包含三类任务：

- 远端题库解析治理：从排查 `<p>暂无解析</p>` 占位解析，扩展为批量重写、验证、同步和远端复验。
- 树莓派性能优化：对比树莓派站点与 Fly 站点加载性能。
- Fly.io 数据迁移到树莓派：明确树莓派为 Docker 部署，并设计树莓派主节点与 Fly 冷备节点。

复盘发现，题库解析治理已经形成稳定重复流程，但不应该固化成 subagent prompt。更合适的沉淀方向是：把“生成解析”的 API prompt、输入组装、输出校验和批次处理做成脚本，使 Codex 或 subagent 只负责调用和验收，而不是把长提示词反复写进对话。

## 结论

优先新增“解析生成脚本化流程”，核心产物是可复用脚本和 API prompt 模板；树莓派相关内容先补项目规则和 Docker 运维参考，不单独新增性能诊断 skill。

## 需求拆解

### 1. 解析生成 API prompt 脚本化

- 当前现状：
  - 解析治理中反复出现批次选择、题面读取、题源核对、解析生成、格式校验、同步远端和远端复验。
  - 这些步骤目前主要靠长对话和人工组织，容易造成上下文膨胀。
- 判断：
  - 重复点不在“怎么派 subagent”，而在“如何稳定构造高质量解析生成请求并验证结果”。
  - 应把稳定逻辑放进脚本和 prompt 模板。
- 修改方案：
  - 在 `scripts/` 下新增解析生成脚本，建议名称：`generate-question-analysis.ps1` 或 `generate-question-analysis.mjs`。
  - 在 `docs/question-bank/` 或 `scripts/templates/` 下新增 API prompt 模板，建议名称：`analysis-generation-api-prompt.md`。
  - 脚本输入：
    - `import_source`
    - 题号范围或题目 ID 列表
    - 题源 Markdown 路径
    - 输出目录
    - 是否只生成 prompt、不调用 API
  - 脚本职责：
    - 读取题面、选项、答案、原解析和题源上下文。
    - 组装统一 API prompt。
    - 支持调用解析生成 API，或输出可复制请求体。
    - 保存每题生成结果。
    - 做结构校验：是否包含思路、关键知识点、选项分析、正确答案解释。
    - 标记低置信结果，进入人工复核队列。
- 影响范围：
  - `scripts/`
  - `docs/question-bank/`
  - 可能新增 `docs/question-bank-governance/`
- 验证方案：
  - 选择一个小批次，例如 3 到 5 道题。
  - 先用 dry-run 生成 API prompt，人工检查 prompt 是否包含题面、答案、题源信息。
  - 再调用 API 生成解析，检查输出结构是否稳定。
  - 用脚本校验结果，确认低质量解析会被标记。

### 2. 题库远端同步脚本模板

- 当前现状：
  - 远端同步反复需要备份、precheck、事务更新、post-verify 和只读复验。
  - 曾出现 SQL 匹配条件过宽的问题，例如使用 `OR question_code` 扩大匹配范围。
- 判断：
  - 远端写库风险高，必须脚本化约束输入和匹配条件。
- 修改方案：
  - 新增同步脚本模板，建议名称：`sync-question-analysis-to-remote.ps1`。
  - 强制使用 `import_batch + import_source + import_question_order` 作为主要匹配条件。
  - 自动生成备份文件。
  - 自动输出 precheck 统计。
  - 使用事务更新。
  - 自动输出 post-verify 统计。
  - 支持只读复验模式。
- 影响范围：
  - `scripts/`
  - 远端数据库运维文档
- 验证方案：
  - 先对 1 到 2 道题执行只读 precheck。
  - 在测试库或受控小批次执行事务更新。
  - 对比备份、更新行数、复验统计。

### 3. 题源一致性检查

- 当前现状：
  - 多次发现解析质量问题实际来自题源不一致，例如选项、代码围栏、缺代码、C++ 标准语境差异。
- 判断：
  - 生成解析前必须先确认题源可靠，否则 API prompt 会放大错误。
- 修改方案：
  - 在解析生成脚本中加入题源检查清单：
    - Markdown 是否含完整题面。
    - 选项数量是否完整。
    - 答案是否存在且唯一。
    - 代码围栏是否闭合。
    - C++ 标准差异是否需要备注。
  - 对不满足条件的题目，不直接生成解析，进入人工复核。
- 影响范围：
  - 解析生成脚本
  - 题源维护流程
- 验证方案：
  - 用历史返工题作为样例，确认脚本能识别缺代码、围栏错误或选项缺失。

### 4. 树莓派 Docker 运维入口规则

- 当前现状：
  - 树莓派性能和迁移任务中都需要用户补充“树莓派是 Docker 部署”。
  - 项目文档同时存在 systemd/Jar 和 Docker 路径。
- 判断：
  - 需要在项目规则中明确：树莓派任务先确认部署方式；如果已知 Docker，直接进入 Docker 文档。
- 修改方案：
  - 更新 `AGENTS.md`：
    - 树莓派迁移、性能、备份、恢复任务开始前先确认实际部署方式。
    - 用户已说明 Docker 时，优先读取 `docker/README.md` 和 `docker/docker-compose.yml`。
  - 补一份 Docker 运维参考，覆盖：
    - JVM 参数
    - Undertow 参数
    - Hikari 参数
    - Cloudflare 缓存检查
    - Fly 冷备
    - Docker Postgres 备份与恢复
- 影响范围：
  - `AGENTS.md`
  - `docker/`
  - `docs/`
- 验证方案：
  - 用树莓派迁移和性能历史任务回放，确认新规则能直接引导到 Docker 路径。

## 执行顺序

1. 新增解析生成 API prompt 模板。
2. 新增解析生成脚本 dry-run 版。
3. 用小批次验证 prompt 质量和输出结构。
4. 新增远端同步脚本模板。
5. 补题源一致性检查。
6. 更新树莓派 Docker 运维入口规则。

## 风险与待确认

- 需要确认解析生成 API 的实际接口、鉴权方式和模型参数。
- 需要确认解析输出是否直接写回 Markdown、数据库中间文件，还是先进入人工复核目录。
- 远端同步脚本必须先支持 dry-run，再考虑真实写库。

## Harness 可执行记录

### 目标

把题库解析治理沉淀为最小可用脚本和文档入口：先稳定生成解析 prompt、题源一致性检查、人工复核队列和远端同步 SQL 模板，再视 API 与数据库环境补真实执行能力。

### 适用范围

- 适用于 GESP/CSP 客观题 Markdown 题源的解析生成、复核和远端同步准备。
- 不适用于未整理成 `## 第N题` 结构的原始 PDF/OCR 文本。
- 不默认调用外部 API，不默认写远端数据库。

### 输入

- `import_batch`、`import_source`、题源 Markdown 路径。
- 题号范围或题目 ID 列表。
- 输出目录。
- 人工复核后的解析 manifest 或 API 结果文件。
- 如需真实 API 或写库，必须另行提供 endpoint、鉴权环境变量、连接串和显式执行参数。

### 执行流程

1. 实现 subagent 新增 prompt 模板和 dry-run 生成脚本。
2. 实现 subagent 新增远端同步 SQL 生成脚本。
3. 实现 subagent 更新项目规则、Docker 运维参考和结构文档索引。
4. 验证 subagent 独立运行脚本 dry-run、检查 SQL 不含宽匹配条件、确认文档索引同步。
5. 主线程验收实现与验证报告，不由实现 subagent 提交 Git。

### 角色分工

- 主线程：确定目标、限制修改范围、调度实现/验证 subagent、最终验收和 Git 策略。
- 实现 subagent：只在限定文件范围内新增脚本和补文档，不提交、不 push。
- 验证 subagent：独立读取变更并执行 dry-run/静态检查，不依赖实现 subagent 的口头结论。
- 人工：复核 `manual-review-queue.json` 中的题源问题和低置信解析。

### 检查点

- 解析生成脚本能对小题号范围输出 prompt、request、manifest 和人工复核队列。
- 远端同步脚本默认只生成 `precheck`、`backup`、`transaction update`、`post-verify` SQL。
- 同步 SQL 以 `import_batch + import_source + import_question_order` 为主匹配条件，不使用 `OR question_code` 扩大范围。
- Docker 运维入口明确树莓派任务先确认部署方式，Docker 已知时优先读取 Docker 文档和 compose。

### 产出

- `scripts/generate-question-analysis.ps1`
- `docs/question-bank/analysis-generation-api-prompt.md`
- `scripts/sync-question-analysis-to-remote.ps1`
- 更新后的 `AGENTS.md`、`docker/README.md`、`docs/project-structure/README.md`、`docs/project-structure/database-deploy.md`
- 本计划文档的 harness 执行记录

### 失败处理

- 题源缺题面、缺答案、选项不完整或代码围栏不闭合时，不直接进入自动同步，写入人工复核队列。
- API endpoint 或鉴权缺失时，脚本必须停止并提示；默认 prompt-only。
- 远端同步未显式 `-Execute -ConfirmWrite` 时，只生成 SQL；precheck 或 backup 失败时不得继续更新。

### Git 策略

本轮采用 subagent 实施/验证，明确不提交 Git、不 push。主线程后续如需提交，应先复查工作区状态和验证结果。
