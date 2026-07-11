# 题目解析质量修复方案

## 背景与现状

- 已确认：题目解析存储在 `t_text_content.content` JSON 的 `analyze` 字段中，题目主表 `t_question` 通过 `info_text_content_id` 关联内容。
- 已确认：管理端已有“题目质量审核”页面，路由为 `/exam/question/review`，后端接口为 `/api/admin/questionReview/*`，可以逐题修改解析和知识点，并写入 `t_question_review_record` 记录审核轮次。
- 已确认：GESP 客观题的长期来源是 `docs/question-bank/GESP` Markdown，批量导入脚本是 `scripts/import-gesp-objective-questions.ps1`。脚本默认按 `import_batch + import_source + import_question_order` 或 `question_code` 原地更新题目，不会改变已有 `question_id`。
- 已确认：导入脚本已经内置解析质量检查，当前规则识别三类问题：包含 `暂无解析`、有效字符数低于阈值、命中模板化短语。
- 已确认：本地 GESP Markdown 可解析 2124 题，质量检查结果为：`暂无解析` 0 题、短解析 233 题、模板短语命中 1809 次、受影响题目 1484 题、总质量问题 2042 个。2024-03、2024-06、2024-09、2024-12 四个批次各 200 题全部命中模板化解析，是优先修复区域。
- 已确认：2026-07-11 通过远端后台接口 `/api/admin/questionReview/page` 拉取 Fly 当前可审核题目 4249 题，按同一套本地规则计算后得到：`暂无解析` 2124 题、短解析 2359 题、模板化解析 1330 题、模板短语命中 1810 次、受影响题目 3611 题、解析审核记录 0 题。
- 已确认：远端 `暂无解析` 题集中在连续 ID `4250-6373`，数量正好 2124 题，解析内容样本为 `<p>暂无解析</p>`；非占位解析题集中在 ID `7897-10621`。按 `subject_id + 题干文本` 粗略去重发现 863 个重复题干组，其中 855 组同时存在占位解析版本和非占位解析版本。
- 判断：远端生产库当前首要问题不是单纯“解析写得差”，而是存在一整套占位解析重复题。批量补解析前必须先确认这批占位题是否被试卷或答题记录引用，再决定软删除、迁移引用或用新内容覆盖。

## 结论

推荐采用“先处理远端占位解析重复题，再修 Markdown 源题库，最后同步 Fly”的路线。少量紧急题目可以直接通过管理端审核页改远端库，但批量修复必须回写 `docs/question-bank/GESP`，否则后续重新导入会覆盖生产库中的人工修复。

## 需求拆解

### 1. 远端库现状统计

- 当前现状：Fly 部署文档记录 Web App 为 `gesp-csp-quiz`，Postgres App 为 `xzs-pg-cb867393296`。应用日志确认生产库为 PostgreSQL 17.7，连接串指向 `xzs-pg-cb867393296.flycast:5432/xzs_cb867393296`。本机没有本地 `psql` 命令；项目导入脚本支持通过 Docker `postgres:17` 镜像执行远端 `psql`。
- 判断：远端统计应先只读执行，避免直接导入或改库。现有后台接口已能拉取审核列表并计算总体质量指标；但要判断占位重复题能否删除，还必须用 SQL 查询试卷题目、答题记录和任务引用。
- 修改方案：新增或临时执行一份只读 SQL，产出远端质量报表。建议先不做写入。
- 影响范围：只读查询 `t_question`、`t_text_content`、`t_question_review_record`。
- 验证方案：确认统计 SQL 返回总题量、GESP 题量、缺解析题数、短解析题数、模板命中题数、受影响题数、占位 ID 段引用数量，并抽样 20 道题核对题干、答案、解析内容。

远端统计 SQL 建议：

```sql
WITH q AS (
  SELECT
    q.id,
    q.subject_id,
    q.import_batch,
    q.import_source,
    q.import_question_order,
    q.question_code,
    q.knowledge_point,
    coalesce(tc.content::jsonb ->> 'titleContent', '') AS title,
    coalesce(tc.content::jsonb ->> 'analyze', '') AS analyze,
    regexp_replace(
      regexp_replace(
        regexp_replace(coalesce(tc.content::jsonb ->> 'analyze', ''), '<[^>]+>', '', 'g'),
        '!\[[^\]]*\]\([^\)]*\)|\[[^\]]+\]\([^\)]*\)',
        '',
        'g'
      ),
      '[#>*_`~\-[:space:]]',
      '',
      'g'
    ) AS compact_analyze
  FROM t_question q
  JOIN t_text_content tc ON tc.id = q.info_text_content_id
  WHERE q.deleted = false AND q.status = 1
),
flagged AS (
  SELECT
    *,
    analyze = '' OR analyze LIKE '%暂无解析%' AS is_placeholder,
    length(compact_analyze) < 60 AS is_short,
    analyze LIKE '%与题干要求一致%'
      OR analyze LIKE '%其余选项要么改变了关键条件%'
      OR analyze LIKE '%其他选项与实际结果%'
      OR analyze LIKE '%按题目涉及的 C++ 语法%'
      OR analyze LIKE '%题目中的表述与 C++ 实际语法%' AS is_template
  FROM q
)
SELECT
  count(*) AS total_questions,
  count(*) FILTER (WHERE import_batch = 'GESP_OBJECTIVE_MD') AS gesp_questions,
  count(*) FILTER (WHERE is_placeholder) AS placeholder_questions,
  count(*) FILTER (WHERE is_short) AS short_questions,
  count(*) FILTER (WHERE is_template) AS template_questions,
  count(*) FILTER (WHERE is_placeholder OR is_short OR is_template) AS affected_questions
FROM flagged;
```

占位重复题引用检查 SQL 建议：

```sql
WITH placeholder_questions AS (
  SELECT q.id, q.subject_id, q.knowledge_point, tc.content::jsonb ->> 'titleContent' AS title
  FROM t_question q
  JOIN t_text_content tc ON tc.id = q.info_text_content_id
  WHERE q.deleted = false
    AND q.id BETWEEN 4250 AND 6373
    AND coalesce(tc.content::jsonb ->> 'analyze', '') LIKE '%暂无解析%'
),
exam_paper_refs AS (
  SELECT (question_item.value ->> 'id')::int AS question_id
  FROM t_exam_paper ep
  JOIN t_text_content ftc ON ftc.id = ep.frame_text_content_id
  CROSS JOIN LATERAL jsonb_array_elements(ftc.content::jsonb) title_item(value)
  CROSS JOIN LATERAL jsonb_array_elements(title_item.value -> 'questionItems') question_item(value)
  WHERE ep.deleted = false
),
task_exam_refs AS (
  SELECT (question_item.value ->> 'id')::int AS question_id
  FROM t_task_exam te
  JOIN t_text_content ftc ON ftc.id = te.frame_text_content_id
  CROSS JOIN LATERAL jsonb_array_elements(ftc.content::jsonb) title_item(value)
  CROSS JOIN LATERAL jsonb_array_elements(title_item.value -> 'questionItems') question_item(value)
  WHERE te.deleted = false
)
SELECT
  (SELECT count(*) FROM placeholder_questions) AS placeholder_questions,
  (SELECT count(*) FROM exam_paper_refs r JOIN placeholder_questions p ON p.id = r.question_id) AS exam_paper_frame_refs,
  (SELECT count(*) FROM task_exam_refs r JOIN placeholder_questions p ON p.id = r.question_id) AS task_exam_frame_refs,
  (SELECT count(*) FROM t_exam_paper_question_customer_answer ca JOIN placeholder_questions p ON p.id = ca.question_id) AS customer_answer_refs,
  (SELECT count(*) FROM t_question_correction_record cr JOIN placeholder_questions p ON p.id = cr.question_id) AS correction_refs;
```

如果生产库里存在历史非数组格式的试卷内容，需要先抽样 `t_exam_paper.frame_text_content_id` 和 `t_task_exam.frame_text_content_id` 对应的 `t_text_content.content`，再调整 JSON 展开路径。

### 2. 远端占位解析重复题处理

- 当前现状：远端 ID `4250-6373` 共 2124 题解析为 `<p>暂无解析</p>`，ID `7897-10621` 为非占位解析题；至少 855 个题干组同时存在占位版和非占位版。
- 判断：如果占位题没有被试卷、答题记录、错题或任务引用，最小风险处理是软删除占位题；如果已有引用，必须先迁移引用到对应非占位题，或只覆盖占位题内容而不删除。
- 修改方案：先用 SQL 建立 `placeholder_question_id -> canonical_question_id` 对照表，匹配优先级为 `question_code/import key`，其次才是规范化题干；确认引用为 0 时执行 `update t_question set deleted = true where id between 4250 and 6373 ...`。若引用不为 0，则把引用关系迁移到 canonical 题后再软删除。
- 影响范围：`t_question.deleted`；如存在引用，还会影响试卷内容 JSON、答题记录和改错记录中的 `question_id`。
- 验证方案：处理后重新拉取 `/api/admin/questionReview/page`，确认 active 总题量从 4249 降到约 2125，`暂无解析` 降到接近 0；学生端试卷、错题本、智能训练不再抽到占位解析题。

### 3. 批量修复解析内容

- 当前现状：本地源题库中模板化问题明显集中在 GESP 2024 全年批次；早期 2023 批次短解析较多；2025 批次主要是选择题模板短语。
- 判断：直接在生产库批量写解析虽然快，但会丢失“源题库即真相”的维护链路。批量修复应优先改 Markdown，再由脚本同步到 Fly。
- 修改方案：按批次分阶段修复 Markdown。每题解析至少说明正确答案原因；选择题还要点出关键干扰项错误原因；程序阅读题要给出关键变量变化或输出推导；判断题要说明判断依据，避免只写“正确/错误”。
- 影响范围：`docs/question-bank/GESP/**/选择题.md`、`docs/question-bank/GESP/**/判断题.md`；同步时影响 Fly 的 `t_text_content.content`。
- 验证方案：每完成一个批次运行 `.\scripts\import-gesp-objective-questions.ps1 -QualityCheck -FailOnQualityIssues`。如果仍需允许极少数短解析，先降低为 `-QualityCheck` 并人工复核输出样本，不直接放行。

### 4. 同步 Fly 远端数据库

- 当前现状：`scripts/import-gesp-objective-questions.ps1 -MigrationSqlOnly` 会生成 `.tmp/runtime/migrate-gesp-markdown-content.sql`，只更新已匹配题目的 `t_text_content` Markdown JSON；完整导入模式会 upsert 题目。
- 判断：如果只是修解析，优先用迁移 SQL 更新匹配题目的内容；如果新增题目或修题目元数据，再使用完整 upsert。
- 修改方案：先备份 Fly Postgres，再执行生成的迁移 SQL。执行前检查 SQL 输出的 `generated_questions`、`matched_questions`、`content_rows_to_update`，确认匹配数量符合预期后再提交。
- 影响范围：Fly 远端 `t_text_content`；不会改变已有答题记录关联的 `question_id`。
- 验证方案：执行后重新跑远端质量统计 SQL，确认本批次 `affected_questions` 下降；抽查管理端 `/exam/question/review` 和学生端错题/试卷解析展示，确认 Markdown、公式、代码块渲染正常。

### 5. 管理端质量队列增强

- 当前现状：管理端审核页能编辑解析并记录审核轮次，但筛选条件没有“缺解析/短解析/模板化解析”。
- 判断：如果要持续修大量解析，单靠关键字搜索效率低，容易漏题。
- 修改方案：给 `QuestionReviewController.page` 增加 `analysisQuality` 筛选项，支持 `PLACEHOLDER`、`SHORT`、`TEMPLATE`、`ANY_ISSUE`；前端审核页增加“解析质量”下拉筛选，并在列表展示质量标签。
- 影响范围：后端 `QuestionReviewController`、前端 `QuestionReviewView.vue`、`frontend/packages/api-client/src/adminQuestion.ts`。
- 验证方案：构造包含空解析、短解析、模板解析和正常解析的样本，验证接口分页、筛选总数、前端标签和保存后审核记录都正确。

## 执行顺序

1. 远端只读统计：保存当前质量基线和占位题样本清单。已通过后台接口确认 active 4249 题、占位解析 2124 题。
2. 引用检查：用 SQL 确认 ID `4250-6373` 占位题是否被试卷、答题记录、错题或任务引用。
3. 处理占位重复题：无引用则软删除；有引用则先建立映射并迁移引用，之后软删除。
4. 修复优先级排序：占位重复题处理完后，再处理短解析、2024 全年模板化解析、2025 选择题模板化解析。
5. 批次修复 Markdown：每次只处理一个年月或一个级别，降低审核压力。
6. 本地质量检查：运行导入脚本 `-QualityCheck`，确认问题数下降并抽查样本。
7. 生成并审阅迁移 SQL：使用 `-MigrationSqlOnly`，确认匹配和待更新数量。
8. 备份并同步 Fly：执行迁移 SQL 后再次跑只读统计。
9. 补管理端质量队列：在批量修复开始前或第一批之后实现，便于后续人工二审。

## 风险与待确认

- Fly CLI 的 Machines/GraphQL 路径仍偶发 EOF，但 Web App 已可访问，后台接口统计已确认远端存在 2124 道占位解析题。
- 本地源题库 `暂无解析` 为 0，远端占位题大概率来自历史导入或重复导入；删除前必须查引用，不能只按 ID 段直接删。
- 模板短语命中不等于解析一定错误，但它高度指向“解释不够具体”。修复时要以题干、答案和选项逐题核对，不能机械替换。
- 修改 Markdown 后如果不同步 Fly，学生端不会看到变化；直接改 Fly 后如果不回写 Markdown，后续导入可能覆盖人工修复。
- 生产库执行前需要备份；即使迁移 SQL 只改内容字段，也会影响学生看到的解析，必须抽样验收。
