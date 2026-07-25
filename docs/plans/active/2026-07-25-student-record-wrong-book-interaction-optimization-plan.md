# 学生端考试记录、错题本与改错连续操作优化方案

状态：active
创建日期：2026-07-25
完成日期：
验证摘要：已在本地 Spring Boot + Neon test 环境使用真实 Chromium 登录学生端完成 3 轮页面测量；本方案阶段仅排查和写方案，未修改功能代码。

## 背景与现状

- 用户反馈三个相互关联的问题：
  1. 考试记录数量不多，但进入页面后要等待较久才能完整显示并互动。
  2. 错题本首屏和切换题目明显偏慢。
  3. 学生提交一道改错后，界面自动切换到“待审核”，继续改下一题前必须手动切回“未提交”。
- 本方案是 `docs/plans/active/2026-07-22-query-performance-optimization-plan.md` 的学生学习闭环专项方案，不替代原有全局查询性能方案。原方案已完成第一批索引和错题列表 CTE 字段收窄；本轮继续处理前端串行等待、后端 N+1 查询和提交后的交互流程。
- 测量环境：
  - 页面：`http://127.0.0.1:8000`
  - 数据库：Neon `test` branch
  - 学生账号：`student`
  - 浏览器：真实 Chromium，由 Playwright CLI 驱动
  - 测量时间：2026-07-25
- test 数据：
  - 考试记录共 2 条。
  - 错题共 67 条，第一页 10 条，其中 7 条未提交、3 条待审核。

## 实测基线

### 页面可互动时间

| 页面/动作 | 第 1 次 | 第 2 次 | 第 3 次 | 中位数 |
|---|---:|---:|---:|---:|
| 考试记录：表格行进入 DOM | 979 ms | 906 ms | 939 ms | 939 ms |
| 考试记录：页面 loading 全部结束 | 1814 ms | 1573 ms | 1496 ms | 1573 ms |
| 错题本：队列进入 DOM | 3120 ms | 2943 ms | 2941 ms | 2943 ms |
| 错题本：首题详情进入 DOM | 3950 ms | 3152 ms | 3059 ms | 3152 ms |
| 错题本：页面 loading 全部结束 | 4612 ms | 4182 ms | 4148 ms | 4182 ms |
| 错题本：已加载后切换到另一题 | - | 2169 ms | - | 2169 ms |

### 关键 API 时间

| API | 本轮样本 | 说明 |
|---|---:|---|
| `/api/student/exampaper/answer/pageList` | 675–778 ms | 当前仅返回 2 条记录 |
| `/api/student/exampaper/answer/paperHistory/180` | 约 393 ms | 在列表请求完成后串行触发 |
| `/api/student/question/answer/wrongQuestionPage` | 约 2503 ms | 返回第一页 10 条 |
| `/api/student/question/answer/select/{id}` | 578–679 ms | 切换题目时第一个请求 |
| `/api/student/question/correction/select/{id}` | 385–696 ms | 等详情返回后请求 |
| `/api/student/question/answer/wrongQuestionHistory/{questionId}` | 382–389 ms | 等改错状态返回后请求 |

## 已确认结论

1. 考试记录慢的主要体感原因不是记录数量，而是页面把主列表和“第一条记录的同卷历史”串成一个 loading。
   - `RecordListView.vue` 的 `loadRecords()` 先等待 `getExamRecordPage()`。
   - 列表返回后又自动 `await viewHistory(records[0])`。
   - 外层 `loading` 直到历史请求结束才关闭，因此主表虽然已经渲染，用户仍要等待第二个请求。
2. 考试记录接口存在按行读取学科的 N+1 查询。
   - `ExamPaperAnswerController.pageList()` 对每条记录调用一次 `subjectService.selectById()`。
   - 当前 2 条记录产生 2 次额外查询；页大小为 10 时最多产生 10 次额外查询。
3. 错题本列表接口存在更严重的 N+1 查询。
   - `studentWrongQuestionPage` SQL 已经联表得到知识点、学科、改错状态。
   - Controller 为生成 `shortTitle`，对每一行再执行：
     - `questionService.selectById(questionId)`
     - `textContentService.selectById(infoTextContentId)`
   - 一页 10 条会增加约 20 次数据库查询。`BaseServiceImpl.selectById()` 直接访问 Mapper，没有缓存。
   - 这解释了列表 SQL 已经收窄、数据量也不大，但 `wrongQuestionPage` 仍约 2.5 秒。
4. 错题本首屏是四段串行瀑布。
   - 列表 `wrongQuestionPage`
   - 首题详情 `select/{id}`
   - 改错状态 `correction/select/{id}`
   - 同题历史 `wrongQuestionHistory/{questionId}`
   - `loadQuestions()` 还会等待 `selectFirstQuestionInCurrentLayer()`，导致队列 loading 覆盖到首题全部附属数据加载结束。
5. 已加载后切换错题仍需 3 个串行 API，实测约 2.17 秒。
6. 提交后跳到“待审核”是确定的前端控制流，不是偶发状态。
   - `submitCorrectionForm()` 提交成功后调用 `await loadCorrection()`。
   - `loadCorrection()` 根据服务端返回状态执行 `activeCorrectionLayer.value = status`。
   - 新提交状态为 `SUBMITTED`，因此活动筛选被强制改成“待审核”。
7. 每个学生 API 还会经过 `WebTokenAuthenticationFilter`，分别查询 token 和用户。
   - 当前错题本首屏 4 个 API 至少重复执行 4 轮认证查询。
   - 本轮不优先增加认证缓存，避免引入账号禁用、角色变化和 token 失效的一致性风险；优先通过合并页面 API 数量减少重复认证成本。

## 结论

推荐按“先解除前端阻塞，再消除后端 N+1，最后合并错题工作区请求并修正连续改错流程”的顺序实施。目标是在本地 Neon test 同口径下，将考试记录主页面可互动时间控制在 0.6–0.9 秒，将错题本完整首题可互动时间控制在 1.6–2.2 秒，并让提交改错后留在当前处理队列、自动进入下一道待处理错题。

## 需求拆解

### 1. 考试记录主列表与同卷历史解耦

- 当前现状：
  - `loadRecords()` 把列表和第一条记录的历史串行等待。
  - 同卷历史是次级信息，却阻塞了主列表操作。
  - 主列表 API 在 2 条记录时仍逐条查询学科。
- 判断：
  - 前端解除阻塞能直接消除约 0.4–0.8 秒的不可互动等待。
  - 去掉学科 N+1 后，列表 API 还能减少 1～9 次数据库往返，收益随页内记录数增加。
- 修改方案：
  1. `loadRecords()` 只负责列表、分页和默认选中行；列表返回后立即关闭主 `loading`。
  2. 默认不自动请求第一条记录的同卷历史。
  3. 用户点击“同卷历史”时再加载；以 `examPaperId` 为 key 做页面生命周期内缓存，重复点击同一试卷不重复请求。
  4. 历史加载只覆盖历史区域，不覆盖主表。
  5. Controller 不再逐条 `subjectService.selectById()`：
     - 主推荐：一次调用 `subjectService.allSubject()` 建立 `id -> name` 映射。
     - 如果后续列表字段继续扩展，再评估由 Mapper 联表直接返回专用 DTO；本轮不为两个字段扩大结构改造。
- 预计收益：
  - 主页面可互动：1573 ms → 600–900 ms，节省约 0.7–1.0 秒，提升约 45%–60%。
  - 列表 API：675–778 ms → 400–550 ms，当前 2 条数据预计节省约 0.15–0.3 秒；满 10 条时收益更明显。
  - 首次进入页面只保留 1 个业务 API；历史请求变为用户需要时才发生。
- 影响范围：
  - `frontend/apps/student/src/views/record/RecordListView.vue`
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/ExamPaperAnswerController.java`
  - `source/xzs/src/test/java/com/mindskip/xzs/controller/student/ExamPaperAnswerControllerTest.java`
- 风险或边界：
  - 页面进入后不再默认展开第一条记录的同卷历史，这是明确的交互变化。
  - 记录行本身已经包含成绩摘要，不影响主表信息完整性。
  - 历史缓存只在当前页面生命周期内有效，刷新后重新获取，避免长期缓存审核或成绩变化。
- 验证方案：
  - 浏览器进入考试记录后，网络面板初始只能看到 `pageList`，不能自动出现 `paperHistory`。
  - 表格 loading 在列表返回后立即消失，历史区域加载不遮挡表格。
  - 点击“同卷历史”才请求历史；同一试卷第二次点击不重复请求。
  - 验证分页、查看试卷、批改、成绩摘要和历史统计结果不变。

### 2. 消除错题列表短标题 N+1 查询

- 当前现状：
  - 一页 10 条错题会为短标题增加约 20 次单条查询。
  - 列表 API 实测约 2.5 秒，是错题本最主要的单接口慢点。
- 判断：
  - 第一批索引和 CTE 收窄已经完成，当前下一优先级应是减少查询次数，而不是继续堆索引。
- 修改方案：
  1. 在 Mapper 增加按 `questionIds` 批量读取 `question_id + info_text_content.content` 的查询，一页最多一次。
  2. Controller 收集当前页去重后的 `questionId`，一次查询后建立 Map。
  3. 继续复用现有 `JsonUtil + HtmlUtil.clear` 生成 `shortTitle`，保证题干清理语义不变。
  4. 删除 `wrongQuestionPage()` 中逐行调用 `questionService.selectById()` 和 `textContentService.selectById()` 的路径。
  5. 保留当前分页、知识点排序、错题次数、最近错题时间和改错状态语义。
- 预计收益：
  - 额外题干查询：约 20 次 → 1 次。
  - `wrongQuestionPage`：约 2503 ms → 700–1000 ms，预计节省 1.5–1.8 秒，提升约 60%–72%。
  - 错题队列进入并可点击：约 2943 ms → 900–1300 ms。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/QuestionAnswerController.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/repository/QuestionMapper.java` 或新增专用查询 Mapper
  - 对应 Mapper XML
  - 可复用或新增只读标题 DTO
  - `QuestionAnswerControllerTest.java`
- 风险或边界：
  - 批量查询必须保持输入去重，并处理题目或 TextContent 已不存在的历史数据。
  - 不能用简单 SQL 正则替代现有 HTML/Markdown 清理，否则短标题可能改变。
- 验证方案：
  - 对同一页改前改后逐项比较 `id/questionId/shortTitle/knowledgePoint/wrongCount/correction_status`。
  - 证明页大小 10 时题干查询固定为 1 次，不随行数增加。
  - 测试题目缺失、TextContent 缺失和重复 questionId。

### 3. 错题列表与首题详情分离 loading

- 当前现状：
  - 列表成功后仍等待首题所有附属请求，队列被 loading 遮罩。
- 判断：
  - 队列是主交互区，应在列表到达时立即可操作；右侧详情可以独立显示骨架或 loading。
- 修改方案：
  1. `loadQuestions()` 只等待列表，写入 `questions/total` 后立即关闭队列 loading。
  2. 首题详情使用独立 `detailLoading`，不再延长 `loading`。
  3. 增加选择请求序号或 `AbortController` 防竞态：用户快速点击多题时，只允许最后一次选择结果写入详情。
  4. 加载新题时保留左侧队列可点击，右侧显示局部 loading。
- 预计收益：
  - 在完成 N+1 优化后，队列预计 0.9–1.3 秒即可互动。
  - 即使详情接口偶发变慢，也不再阻塞筛选、分页和选择其它题。
- 影响范围：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
- 风险或边界：
  - 仅分离 loading 不处理竞态，会出现先点的慢请求覆盖后点的快请求，因此竞态保护必须同时完成。
- 验证方案：
  - 使用人为延迟的详情请求，确认左侧队列仍可点击。
  - 连续快速点击两道题，最终详情必须对应最后一次点击。
  - 翻页期间旧详情不能覆盖新页选择。

### 4. 合并错题工作区详情请求

- 当前现状：
  - 每次选择错题依次请求详情、改错状态、同题历史，实测约 2.17 秒。
  - 三个请求会重复三轮 token/用户认证查询。
- 判断：
  - 只在前端并发可以减少一部分串行时间，但仍保留三个 HTTP 请求和三轮认证。
  - 页面需要的是同一个“错题工作区”数据，应由一个只读组合接口返回。
- 修改方案：
  1. 新增只读接口，例如：
     - `POST /api/student/question/answer/workspace/{customerAnswerId}`
  2. 返回专用 `WrongQuestionWorkspaceVM`：
     - `questionVM`
     - `questionAnswerVM`
     - `correction`
     - `wrongHistory`
  3. 接口先校验 customer answer 属于当前用户且确实为错题，再查询其它数据。
  4. 前端 `selectQuestion()` 改为一次请求，不再调用现有三个接口。
  5. 现有接口先保留，避免影响其它页面；确认无调用后再决定是否清理。
  6. 服务端内部可顺序执行现有查询，本阶段先通过减少 HTTP/认证次数获得收益；如果组合接口仍慢，再根据单段计时决定是否并行或继续批量化。
- 预计收益：
  - 选择题目请求数：3 → 1。
  - 每次切题：2169 ms → 700–1000 ms，预计节省 1.2–1.5 秒，提升约 55%–70%。
  - 错题本完整首题可互动：4182 ms → 1600–2200 ms，预计节省 2.0–2.6 秒，提升约 48%–62%。
- 影响范围：
  - `frontend/packages/api-client/src/studentExam.ts`
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/QuestionAnswerController.java`
  - 新增 `WrongQuestionWorkspaceVM`
  - `QuestionAnswerControllerTest.java`
- 风险或边界：
  - 组合接口不能绕过现有答案归属校验。
  - 返回字段应复用现有 VM，避免同一数据产生两套字段含义。
  - 组合接口失败时右侧显示可重试状态，左侧列表保持可用。
- 验证方案：
  - 浏览器切换题目时只能出现一个 workspace 请求。
  - 详情、答案、审核状态、审核意见和错误历史与现有三个接口结果一致。
  - 用其他学生的 customerAnswerId 请求必须失败。
  - 快速切题和接口失败时不能显示错题错配的数据。

### 5. 提交后保持当前处理队列并自动进入下一题

- 当前现状：
  - 提交成功后额外请求一次 correction/select。
  - `loadCorrection()` 强制把活动层改成服务端状态，导致自动跳到“待审核”。
- 判断：
  - “提交一题后继续下一道未提交题”是连续处理错题的主流程。
  - 当前行为把系统状态展示优先于用户任务连续性。
- 修改方案：
  1. `loadCorrection()` 只更新所选题的详情状态，不再修改 `activeCorrectionLayer`。
  2. 提交接口返回最小确认数据：
     - `customerAnswerId`
     - `correctionId`
     - `reviewStatus=SUBMITTED`
  3. 提交成功后不再调用 `loadCorrection()`：
     - 本地把当前行状态更新为 `SUBMITTED`。
     - 保持用户当前所在层次。
     - 提示“已提交，已移至待审核”。
  4. 如果用户在“未提交”：
     - 当前题从列表过滤结果中移除。
     - 自动选择同组下一题；同组没有则选择当前页下一道未提交题。
     - 当前页没有未提交题时显示完成状态，不自动跳到待审核。
  5. 如果用户在“被驳回”重新提交，保持“被驳回”层并进入下一道被驳回题。
  6. 后台 AI 审核触发逻辑保持不变。
- 预计收益：
  - 提交成功后减少一次 correction/select，节省约 0.4–0.7 秒。
  - API 返回后本地队列状态更新时间目标小于 100 ms。
  - 取消一次人工切换筛选；下一题 workspace 目标 0.7–1.0 秒内可操作。
- 影响范围：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - `frontend/packages/api-client/src/studentExam.ts`
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/QuestionCorrectionController.java`
  - 新增提交响应 VM
  - `QuestionCorrectionControllerTest.java`
- 风险或边界：
  - AI 审核可能在提交后很快改变状态；本地先显示 `SUBMITTED`，刷新或进入对应层时再获取最新审核状态。
  - 当前状态计数是“当前分页内计数”，不是全部 67 条的全局状态计数。本轮先保证当前页连续处理；全局按状态分页应单独作为后续结构改造。
  - 提交失败时不能提前移动当前行或清空表单。
- 验证方案：
  - 未提交题提交成功后，活动筛选仍为“未提交”，当前行移出并自动选择下一题。
  - 被驳回题重新提交后，仍留在“被驳回”。
  - 网络中不能出现提交成功后的 correction/select 请求。
  - 提交失败、重复提交、已通过和无权限场景保持当前题及表单。
  - 确认 `triggerAfterCommit` 对首次提交和重新提交仍分别触发。

### 6. 后续：按改错状态做服务端分页

- 当前现状：
  - 后端先对全部错题分页，前端再按改错状态过滤。
  - 状态按钮数字只统计当前页，分页总数却是全部错题。
- 判断：
  - 这不会直接造成当前 4 秒等待，但会在错题增多后影响连续处理：某一页可能显示“当前层次暂无错题”，实际下一页仍有该状态数据。
- 推荐边界：
  - 不与第一批性能改动混在同一提交中。
  - 第一批完成并验证后，再增加 `correctionStatus` 服务端筛选、状态总数和按状态分页。
  - 上线前对 lateral correction 查询做 `EXPLAIN (ANALYZE, BUFFERS)`；只有计划需要时才新增状态组合索引。
- 验证方案：
  - 每个状态的总数、分页总数和实际数据一致。
  - 提交后未提交总数减一、待审核总数加一。
  - 状态筛选不能破坏知识点和错题次数排序。

## 推荐执行顺序

1. 前端先解除考试记录和错题队列的阻塞 loading，并补快速切题竞态保护。
2. 后端消除考试记录学科 N+1 和错题标题 N+1；保持现有接口字段与排序。
3. 增加错题 workspace 组合接口，前端从 3 个选择请求切换为 1 个。
4. 修改提交响应和连续改错交互，取消提交后的强制状态层切换。
5. 使用同一学生账号、同一 test 数据、同一浏览器脚本做改前改后 3 轮中位数对比。
6. 第一批验收后，再决定是否实施全局按状态分页。

## 验收门槛

### 性能

| 指标 | 当前中位数 | 第一批目标 |
|---|---:|---:|
| 考试记录主表可互动 | 1573 ms | 600–900 ms |
| 考试记录列表 API | 675–778 ms | 400–550 ms |
| 错题队列可互动 | 2943 ms | 900–1300 ms |
| 错题本首题完整可互动 | 4182 ms | 1600–2200 ms |
| 已加载后切换错题 | 2169 ms | 700–1000 ms |
| 提交后额外状态查询 | 385–696 ms | 0 ms |

### 功能

- 考试记录分页、成绩、查看试卷、批改、同卷历史统计不变。
- 错题短标题、题目详情、答案、解析、审核状态、审核意见和同题历史不变。
- 首次提交、驳回后重提、重复提交、已通过、无权限等边界不回归。
- 提交后不跳到待审核，继续当前处理队列。

### 验证层级

1. 后端单元测试：
   - Controller 结果映射、批量标题、workspace 权限、提交响应和 AI after-commit。
2. API 对比：
   - 保存改前改后 JSON，比较分页、排序和核心字段。
3. 数据库观察：
   - 开启测试环境 SQL 计数或使用测试拦截器，证明错题标题查询从约 20 次降到 1 次。
4. 浏览器回归：
   - 真实登录、导航、切题、提交、连续处理、历史展开。
   - 记录请求数量、请求顺序、页面可互动时间和控制台错误。
5. 构建与静态一致性：
   - 学生端生产构建。
   - 后端相关测试与 package。
   - `scripts/verify-web-static-consistency.ps1`。

## 风险与待确认

- 待确认：考试记录进入页面后，是否接受“同卷历史改为点击后加载”。本方案主推荐接受，因为它是次级信息且当前直接阻塞主表。
- 待确认：连续改错时，当前页没有下一道同状态题后，是显示“本页已完成”，还是自动翻到下一页。建议第一批显示完成状态，待服务端状态分页完成后再自动跨页。
- 风险：组合 workspace 接口扩大单次响应；需要对包含长题干、解析和多次错误历史的题目检查响应体大小。
- 风险：前端解除串行等待后必须处理请求竞态，否则快速切题可能显示旧请求结果。
- 风险：认证查询仍是所有 API 的固定成本。若页面专项优化后单 API 仍稳定高于目标，再单独设计短 TTL token/user 缓存，不能在本轮顺手加入。

## 收尾记录

- 完成状态：
- 归档日期：
- 归档原因：
