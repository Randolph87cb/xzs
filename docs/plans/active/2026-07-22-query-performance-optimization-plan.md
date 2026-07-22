# 查询性能优化排查与实施方案

状态：active
创建日期：2026-07-22
完成日期：
验证摘要：

## 背景与现状

- 用户反馈“有时候查数据延迟有点高”，本轮先做代码和索引层面的静态排查，未直接连接 Neon test 或 production 数据库执行 `EXPLAIN ANALYZE`。
- 后端使用 Spring Boot + MyBatis + PageHelper + PostgreSQL。分页入口主要在 `source/xzs/src/main/java/com/mindskip/xzs/service/impl/*ServiceImpl.java`，SQL 在 `source/xzs/src/main/resources/mapper/*.xml`。
- 当前已有的主要业务索引集中在 `V1__baseline_schema.sql` 和 `V7__add_student_history_wrong_question_indexes.sql`：班级、用户班级角色、答卷班级时间、错题历史等已有基础索引，但题目筛选、试卷筛选、用户登录/搜索、任务答题记录、日志等高频查询仍缺少匹配索引。

## 结论

优先处理智能训练抽题、题目/试卷/答卷/用户列表索引、班级排行 `COALESCE` 查询形态和日志/任务记录索引；同时补一套只读 SQL 观测脚本，用测试库和生产库的 `EXPLAIN (ANALYZE, BUFFERS)` 验证真实瓶颈后再上线迁移。

## 需求拆解

### 1. 智能训练随机抽题

- 当前现状：
  - `QuestionMapper.xml` 的 `selectRandomBySubjectId` 和 `selectRandomBySubjectIdAndKnowledgePoint` 使用 `ORDER BY random() LIMIT ...`。
  - `ExamPaperServiceImpl.selectSmartTrainingQuestions` 会按规则循环调用 `selectCountBySubjectIdAndKnowledgePoint` 和 `selectRandomBySubjectIdAndKnowledgePoint`，知识点越多，查询次数越多。
- 判断：
  - `ORDER BY random()` 在 PostgreSQL 中通常需要扫描符合条件的候选行并排序，题库增大后会成为最明显的延迟来源之一。
  - 当前 `t_question` 除主键和导入唯一索引外，没有覆盖 `deleted/status/subject_id/knowledge_point` 的筛选索引。
- 修改方案：
  - 新增迁移：`CREATE INDEX CONCURRENTLY` 或普通 Flyway 迁移索引，建议先加 `t_question(deleted, status, subject_id, knowledge_point, id)`，必要时再加 `t_question(deleted, status, subject_id, id)`。
  - 将抽题改成两阶段：先用索引条件取候选 `id` 范围或候选 `id` 列表，再在应用层随机采样；对每个知识点可以一次查询候选题 `id` 和必要字段，避免每个知识点先 count 再 random 排序。
  - 对配置规则数量较少的场景，保留现有行为作为回退，但不要继续使用全表随机排序作为主路径。
- 影响范围：
  - 学生端智能训练生成、管理端智能训练配置后的出题效果。
  - 涉及 `QuestionMapper.xml`、`QuestionMapper.java`、`ExamPaperServiceImpl.java` 和新 Flyway 迁移。
- 验证方案：
  - 在 test branch 用真实题库执行现有随机 SQL 和新方案 SQL 的 `EXPLAIN (ANALYZE, BUFFERS)`。
  - 调用智能训练生成接口，确认题数、知识点下限、题型内容和无重复题不回归。
  - 对题库规模做至少 1k、10k、50k 级别样本压测或模拟数据压测。

### 2. 题目、试卷和答卷列表索引

- 当前现状：
  - `QuestionMapper.page` 按 `deleted`、`grade_level`、`subject_id`、`question_type`、`knowledge_point` 过滤，服务层通过 PageHelper 加 `id desc`。
  - `ExamPaperMapper.page/studentPage/indexPaper` 按 `deleted`、`subject_id`、`grade_level`、`paper_type` 过滤并按 `id desc` 取列表。
  - `ExamPaperAnswerMapper.studentPage` 按 `create_user`、可选 `subject_id` 过滤；`adminPage` 按 `subject_id`、班级过滤并分页。
  - 当前 schema 中没有题目列表和试卷列表的组合索引；答卷已有 `class_id, create_time` 和 `create_user, exam_paper_id, create_time desc`，但学生记录列表的 `create_user + subject_id + id/create_time` 不完全匹配。
- 判断：
  - 列表页是高频路径。没有覆盖筛选和排序的组合索引时，数据量增大后分页 count 和第一页加载都会变慢。
  - PageHelper 会额外生成 count SQL，索引缺失会把一次列表请求放大为两次慢查询。
- 修改方案：
  - 新增候选索引：
    - `t_question(deleted, subject_id, grade_level, question_type, knowledge_point, id desc)`。
    - `t_exam_paper(deleted, paper_type, subject_id, grade_level, id desc)`。
    - `t_exam_paper_answer(create_user, subject_id, id desc)`。
    - `t_exam_paper_answer(subject_id, class_id, id desc)`，配合管理端答卷列表。
  - 对 `indexPaper` 如果固定只取最新 5 条，保留明确 `ORDER BY id DESC LIMIT 5`，并确认索引能覆盖 `paper_type/subject_id/grade_level/deleted/id`。
  - 高页码慢时，再评估从 offset 分页改为基于 `id` 的游标分页；先不作为第一阶段改动。
- 影响范围：
  - 管理端题目列表、试卷列表、答卷列表；学生端试卷中心、考试记录。
- 验证方案：
  - 在 test branch 对典型筛选组合跑 `EXPLAIN (ANALYZE, BUFFERS)`，确认从 Seq Scan/Sort 降到 Index Scan 或 Bitmap Index Scan。
  - 页面验收：题目列表、试卷列表、学生考试记录分页、筛选条件和排序一致。

### 3. 班级排行和班级过滤查询形态

- 当前现状：
  - `UserMapper.selectClassRankingBase` 对答卷和改错记录使用 `COALESCE(record.class_id, user.class_id) = #{classId}` 聚合。
  - `ExamPaperAnswerMapper.adminPage` 对答卷列表也使用 `COALESCE(a.class_id, u.class_id)` 过滤班级。
  - schema 已有 `t_exam_paper_answer(class_id, create_time)`、`t_question_correction_record(class_id, review_status, submit_time)` 和 `t_user(class_id, role, deleted)`。
- 判断：
  - `COALESCE` 放在过滤条件上会削弱普通列索引利用；历史数据需要回退到用户班级时合理，但实时查询不宜长期依赖表达式过滤。
- 修改方案：
  - 先做一次数据修复/回填检查：统计 `t_exam_paper_answer.class_id is null`、`t_question_correction_record.class_id is null` 的数量。
  - 如果历史空值可回填，新增迁移或维护脚本把记录表 `class_id` 回填为提交时用户班级；后续查询优先直接用 `record.class_id = #{classId}`。
  - 对仍需兼容空值的短期阶段，将查询拆成两段 `record.class_id = ? OR (record.class_id IS NULL AND user.class_id = ?)`，并用 `EXPLAIN` 比较是否优于 `COALESCE`。
- 影响范围：
  - 学生端班级排行、教师端答卷列表、改错统计。
- 验证方案：
  - 用 test branch 对有空 `class_id` 和无空 `class_id` 两种数据跑结果一致性 SQL。
  - 页面验收班级排行人数、排序、提交数、改错数和教师权限过滤。

### 4. 错题本和答题明细

- 当前现状：
  - `ExamPaperQuestionCustomerAnswerMapper.studentWrongQuestionPage` 已有专门的 `idx_customer_answer_user_question_wrong_time` 部分索引，方向正确。
  - `selectListByPaperAnswerId` 按 `exam_paper_answer_id` 查答题明细并 `order by item_order`，当前未看到匹配索引。
  - `studentWrongQuestionHistory` 连接答卷和改错记录，主要依赖 V7 的错题历史索引。
- 判断：
  - 错题本列表已有针对性优化；答题明细在每次查看答卷时会按答卷 ID 拉全部题目，缺 `exam_paper_answer_id,item_order` 索引时答题记录多了会慢。
- 修改方案：
  - 新增 `t_exam_paper_question_customer_answer(exam_paper_answer_id, item_order)`。
  - 保留 V7 的错题历史索引；如 `studentWrongQuestionPage` 在真实数据上仍慢，再考虑将 `wrong_answers` CTE 改为只投影必要列，减少排序和聚合宽度。
- 影响范围：
  - 学生查看考试记录详情、错题本。
- 验证方案：
  - 对 `selectListByPaperAnswerId` 跑 EXPLAIN，确认按索引取题目顺序。
  - 打开考试记录详情，确认题目顺序、答案和判分不变。

### 5. 用户、任务、日志和登录查询

- 当前现状：
  - `UserMapper.getUserByUserName/getUserByUserNamePwd/selectByWxOpenId` 是登录和微信登录高频查询，但 schema 未看到 `user_name`、`wx_open_id` 的唯一或普通索引。
  - `UserMapper.userPage/selectByUserName/selectStudentByUserNameInClasses` 使用 `LIKE concat('%', value, '%')`，普通 B-tree 索引无法支持前置通配符。
  - `TaskExamCustomerAnswerMapper.getByTUid/selectByTUid` 按 `task_exam_id/create_user` 查询，当前未看到匹配索引。
  - `UserEventLogMapper.getUserEventLogByUserId/page` 按 `user_id`、`id desc` 或 `user_name` 查日志，当前未看到匹配索引。
- 判断：
  - 登录查询缺索引会直接影响所有会话建立和鉴权相关链路。
  - 模糊搜索如果数据量不大可以暂缓；若学生数明显增长，需要 `pg_trgm` 或改成前缀搜索。
- 修改方案：
  - 新增索引：
    - `t_user(deleted, user_name)`，若业务要求用户名唯一，改为部分唯一索引 `unique where deleted=false`。
    - `t_user(deleted, wx_open_id)`，空值较多时用部分索引 `where deleted=false and wx_open_id is not null`。
    - `t_task_exam_customer_answer(task_exam_id, create_user)` 和 `t_task_exam_customer_answer(create_user, task_exam_id)`，结合 EXPLAIN 选择一个或两个。
    - `t_user_event_log(user_id, id desc)`，管理端按用户名精确查时补 `t_user_event_log(user_name, id desc)`。
  - 学生/用户名模糊搜索先限制输入防抖和最小长度；后续如确实慢，再启用 PostgreSQL `pg_trgm` 并加 GIN trigram 索引。
- 影响范围：
  - 登录、微信登录、用户列表搜索、任务答题状态、用户日志。
- 验证方案：
  - 登录、微信登录、任务列表/学生任务状态、用户日志分页全链路验证。
  - 对模糊搜索分别测试空输入、1 字符、常见姓名/用户名。

### 6. 观测与慢查询定位

- 当前现状：
  - 应用配置有 Hikari 参数，Docker Compose 生产默认连接池较保守；未看到应用侧慢 SQL 日志、接口耗时日志或数据库 `pg_stat_statements` 使用说明。
  - 本轮本地没有直接可用的 `psql`/数据库客户端库，未执行线上/测试库 EXPLAIN。
- 判断：
  - 没有观测会导致靠感觉优化，容易加错索引或漏掉真实慢点。
- 修改方案：
  - 增加一个只读运维脚本或文档：从 `.env.neon-test` 读取测试库连接，不打印 secret，输出表行数、索引清单、`pg_stat_user_indexes`、关键 SQL 的 `EXPLAIN (ANALYZE, BUFFERS)`。
  - 在生产库只执行只读观测，避免在生产直接跑会写入或锁表的维护操作。
  - 如果 Neon 支持，打开或查询 `pg_stat_statements`，按总耗时和平均耗时找 Top SQL。
- 影响范围：
  - 运维脚本和排查文档，不影响业务。
- 验证方案：
  - 脚本在 test branch 能输出关键 SQL 计划且不包含连接串、用户名密码。
  - 生产只读执行前先确认连接的是 production branch。

## 执行顺序

1. 先补观测脚本/文档，在 Neon test branch 采集关键表行数、索引和慢 SQL 执行计划。
2. 第一批上线低风险索引：题目、试卷、学生答卷、答题明细、登录/微信登录、任务答题记录、用户日志。
3. 改智能训练抽题逻辑，替换 `ORDER BY random()` 主路径，并保留小数据量回退。
4. 处理班级排行和答卷列表的 `COALESCE` 查询：先统计和回填历史 `class_id`，再改 SQL。
5. 视真实数据决定是否做用户模糊搜索的 `pg_trgm`，以及是否把大列表改成游标分页。

## 风险与待确认

- 待确认：线上延迟主要发生在哪些页面或操作，例如智能训练生成、错题本、答卷列表、班级排行、登录、管理端题目搜索。
- 待确认：production 和 test branch 当前数据量、空 `class_id` 历史数据规模、Neon 是否已启用 `pg_stat_statements`。
- 风险：新增索引会增加写入成本和存储占用；在生产大表上建索引应优先评估 `CREATE INDEX CONCURRENTLY`，但 Flyway 默认事务行为与并发建索引需要单独处理。
- 风险：智能训练抽题逻辑调整后，要保证知识点权重、最小题数、题目不重复和题型展示都不回归。

## 收尾记录

- 完成状态：
- 归档日期：
- 归档原因：
