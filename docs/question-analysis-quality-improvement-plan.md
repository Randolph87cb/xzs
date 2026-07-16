# 题目解析质量修复方案

> 现行远端约定：本文早期内容中的“Fly 远端”是迁移前的历史表述。2026-07-16 之后，默认远端写入目标是树莓派主站 `https://gesp-csp-quiz.randolph87.top` 背后的 Docker PostgreSQL；Fly 只作为冷备，在树莓派验证通过后由树莓派 dump 覆盖同步。

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

推荐采用“先处理远端占位解析重复题，再建立逐题人工审核队列，最后按批次同步 Fly”的路线。最终目标是 active 题库无重复题、每道题都有经过人工确认的高质量解析。解析重写必须逐题人工确认，不使用程序、脚本、模型或其他自动化方式批量生成或批量改写解析；自动化只允许用于排查、列队列、引用检查、同步人工确认结果和验收统计。

## 硬性原则

- 解析内容逐题确认：每一道题都要看题干、选项、正确答案和现有解析后再重写或确认通过。
- 禁止批量生成解析：不得用程序、脚本、模型、规则替换或模板拼接批量产出解析文本。
- 允许自动化辅助：可以用 SQL/脚本查重复、查引用、生成待审清单、统计质量指标、同步已人工确认的 Markdown 到树莓派远端，并在验证通过后同步 Fly 冷备，但不能让自动化决定解析内容。
- 源题库优先：最终确认后的解析必须回写 `docs/question-bank/GESP`，树莓派数据库作为线上运行副本，Fly 数据库作为冷备副本。
- 可追溯：每批修订要保留题目来源、题号、处理人、处理结果和抽查记录，避免“改过但无法解释为什么”。

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

### 3. 人工解析修订工作流

- 当前现状：本地源题库中模板化问题明显集中在 GESP 2024 全年批次；早期 2023 批次短解析较多；2025 批次主要是选择题模板短语。远端后台审核页能逐题改解析并记录审核轮次，但还没有“质量队列”和“人工完成清单”。
- 判断：解析质量提升是内容工程，不是数据清洗。需要慢慢做，每次只处理小批量，避免为了快速清零指标而写出新的模板化解析。
- 修改方案：
  1. 建立待审清单：按 `年月/级别/题型/题号` 列出每道题，标记问题类型为 `缺解析`、`短解析`、`模板化`、`疑似重复`、`待二审`、`已通过`。
  2. 每次只领取一个小批次：建议一次处理 10 到 25 题，处理完再进入下一批。
  3. 逐题人工重写：人工阅读题干、选项、答案和相关 C++/计算机基础知识，写出针对该题的解释。
  4. 二次人工复核：另一轮人工检查答案是否正确、推理是否完整、措辞是否适合学生阅读。
  5. 回写源文件：通过普通文本编辑把确认后的解析写回 `docs/question-bank/GESP/**` 对应 Markdown，不使用批量替换。
  6. 同步线上：只把已经人工确认的源文件变更同步到树莓派远端；验证通过后再同步 Fly 冷备。
- 影响范围：`docs/question-bank/GESP/**/选择题.md`、`docs/question-bank/GESP/**/判断题.md`、后台审核记录、树莓派远端 `t_text_content.content` 和 Fly 冷备快照。
- 验证方案：每批处理后抽查 100% 的本批题目，确认题干、答案、解析与 Markdown 渲染一致；再运行质量统计确认没有新增 `暂无解析`、模板短语或明显短解析。

解析验收标准：

- 选择题：说明为什么正确选项成立；至少指出一个关键干扰项为什么不成立；涉及代码时给出关键执行过程。
- 判断题：明确判断依据；如果说法错误，要指出错在哪里；如果说法正确，要说明适用条件。
- 程序阅读题：给出关键变量变化、循环次数、输出推导或语法规则，不能只写“运行后可得”。
- 概念题：给出定义、边界或反例，避免只复述选项。
- 表达式/运算题：写出关键计算步骤，特别是整除、取模、优先级、类型转换、短路求值等易错点。
- 语言表达：面向学生，短句优先；避免“与题干要求一致”“其他选项不满足题意”这类空泛模板句。

### 4. 重复题治理

- 当前现状：远端已确认存在占位版与非占位版混合重复；本地源题库也需要最终确认是否存在跨年份、跨级别、题干高度相似但来源不同的题。
- 判断：重复题不能只按题干文本机械删除，因为真题可能跨年份复用、选项或答案细节可能不同。最终 active 题库要无重复，但删除/合并必须经过人工确认。
- 修改方案：
  1. 自动化只生成“疑似重复清单”，候选规则包括完全相同题干、规范化题干相同、题干高度相似、同题干不同答案。
  2. 人工逐组判定：标记为 `确认为重复`、`相似但保留`、`不同题`。
  3. 对确认为重复的题，选择 canonical 题：优先保留有正式来源元数据、解析质量高、已被试卷/答题记录引用少或可稳定迁移的一条。
  4. 对需要保留历史真题出处的重复题，不在 active 训练题库重复出现；可以保留来源映射或备注，不让智能训练重复抽取。
  5. 删除方式优先软删除，必要时迁移引用，不做物理删除。
- 影响范围：`t_question.deleted`、试卷 frame JSON、答题记录、改错记录、源题库来源映射。
- 验证方案：重复清理后按题干规范化规则重新统计 active 题库，确认确认为重复的组不再出现；抽查智能训练和固定试卷不再抽到重复题。

### 5. 同步树莓派远端数据库并备份到 Fly

- 当前现状：`scripts/import-gesp-objective-questions.ps1 -MigrationSqlOnly` 会生成 `.tmp/runtime/migrate-gesp-markdown-content.sql`，只更新已匹配题目的 `t_text_content` Markdown JSON；完整导入模式会 upsert 题目。
- 判断：如果只是同步已经人工确认的解析，优先用迁移 SQL 更新匹配题目的内容；如果新增题目、修题目元数据或清理重复题，再使用单独审阅过的 SQL。同步脚本不能生成解析，只能搬运人工确认内容。当前默认写入目标是树莓派主库，不是 Fly。
- 修改方案：先备份树莓派 Postgres，再对树莓派主库执行生成的迁移 SQL。执行前检查 SQL 输出的 `generated_questions`、`matched_questions`、`content_rows_to_update`，确认匹配数量符合预期后再提交。树莓派验证通过后，再将树莓派 dump 恢复到 Fly Postgres 作为冷备。
- 影响范围：树莓派远端 `t_text_content`，以及后续 Fly 冷备快照；不会改变已有答题记录关联的 `question_id`。
- 验证方案：执行后重新跑远端质量统计 SQL，确认本批次 `affected_questions` 下降；抽查管理端 `/exam/question/review` 和学生端错题/试卷解析展示，确认 Markdown、公式、代码块渲染正常。

### 6. 管理端质量队列增强

- 当前现状：管理端审核页能编辑解析并记录审核轮次，但筛选条件没有“缺解析/短解析/模板化解析”。
- 判断：如果要持续修大量解析，单靠关键字搜索效率低，容易漏题。
- 修改方案：给 `QuestionReviewController.page` 增加 `analysisQuality` 筛选项，支持 `PLACEHOLDER`、`SHORT`、`TEMPLATE`、`ANY_ISSUE`；前端审核页增加“解析质量”下拉筛选，并在列表展示质量标签。该功能只负责排队和记录，不自动生成解析。
- 影响范围：后端 `QuestionReviewController`、前端 `QuestionReviewView.vue`、`frontend/packages/api-client/src/adminQuestion.ts`。
- 验证方案：构造包含空解析、短解析、模板解析和正常解析的样本，验证接口分页、筛选总数、前端标签和保存后审核记录都正确。

## 执行顺序

1. 远端只读统计：保存当前质量基线和占位题样本清单。已通过后台接口确认 active 4249 题、占位解析 2124 题。
2. 引用检查：用 SQL 确认 ID `4250-6373` 占位题是否被试卷、答题记录、错题或任务引用。
3. 处理占位重复题：无引用则软删除；有引用则先建立映射并迁移引用，之后软删除。
4. 建立人工待审清单：按批次列出每一道需要人工处理的题，不生成解析内容。
5. 小批量逐题修订：一次 10 到 25 题，人工重写、人工二审、回写 Markdown。
6. 重复题逐组确认：自动化只提供候选组，人工决定是否合并、保留或软删除。
7. 本地质量检查：运行导入脚本 `-QualityCheck`，确认问题数下降并抽查样本。
8. 生成并审阅迁移 SQL：使用 `-MigrationSqlOnly`，确认匹配和待更新数量。
9. 备份并同步树莓派远端：执行迁移 SQL 后再次跑只读统计和页面抽查。
10. 备份到 Fly 冷备：树莓派验证通过后，将树莓派 dump 恢复到 Fly。
11. 补管理端质量队列：在批量修复开始前或第一批之后实现，便于后续人工二审。

## 风险与待确认

- Fly CLI 的 Machines/GraphQL 路径仍偶发 EOF，但 Web App 已可访问，后台接口统计已确认远端存在 2124 道占位解析题。
- 本地源题库 `暂无解析` 为 0，远端占位题大概率来自历史导入或重复导入；删除前必须查引用，不能只按 ID 段直接删。
- 模板短语命中不等于解析一定错误，但它高度指向“解释不够具体”。修复时要以题干、答案和选项逐题核对，不能机械替换。
- 解析质量提升会很慢，这是预期结果。为了质量，不以一次性清零统计指标为目标，而以逐题通过人工验收为目标。
- 自动化重复检测可能有误报，尤其是跨年份复用题、同题干不同选项、同概念不同问法，必须人工判定。
- 修改 Markdown 后如果不同步树莓派远端，学生端不会看到变化；直接改树莓派或 Fly 后如果不回写 Markdown，后续导入可能覆盖人工修复。
- 生产库执行前需要备份；即使迁移 SQL 只改内容字段，也会影响学生看到的解析，必须抽样验收。
