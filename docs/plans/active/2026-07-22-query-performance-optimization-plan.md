# 查询性能优化排查与实施方案

状态：active
创建日期：2026-07-22
完成日期：
验证摘要：第一阶段已完成本地静态检查和后端编译；当前环境无 `psql`，数据库迁移仅做文件顺序和只含索引语句的静态检查，未连接 production。

## 背景与现状

- 用户反馈“有时候查数据延迟有点高”，本轮已经完成代码/索引层面的静态排查、Neon test branch 只读 `EXPLAIN` 验证，以及本地和远端真实浏览器页面测速。
- 后端使用 Spring Boot + MyBatis + PageHelper + PostgreSQL。分页入口主要在 `source/xzs/src/main/java/com/mindskip/xzs/service/impl/*ServiceImpl.java`，SQL 在 `source/xzs/src/main/resources/mapper/*.xml`。
- 当前已有的主要业务索引集中在 `V1__baseline_schema.sql` 和 `V7__add_student_history_wrong_question_indexes.sql`：班级、用户班级角色、答卷班级时间、错题历史等已有基础索引，但题目筛选、试卷筛选、用户登录/搜索、任务答题记录、日志等高频查询仍缺少匹配索引。

## Test 环境实测结论

- 测试时间：2026-07-22。
- 测试环境：从 `.env.neon-test` 连接 Neon test branch，只执行只读统计和 `EXPLAIN (ANALYZE, BUFFERS)`。
- 测试库规模偏小：`t_user=10`、`t_question=5225`、`t_exam_paper=99`、`t_exam_paper_answer=5`、`t_exam_paper_question_customer_answer=142`、`t_question_correction_record=12`、`t_task_exam_customer_answer=1`、`t_user_event_log=82`。
- 因为测试库数据量小，多数接口 SQL 实际执行时间在 1 ms 内，无法直接复现用户体感的高延迟；本次结论主要依据执行计划形态判断“数据放大后会先慢在哪里”。
- 已确认的执行计划风险：
  - 题目列表按 `subject_id` 查第一页时走主键倒序扫描再过滤，`subject_id=1` 过滤前跳过 825 行；对应 count 查询对 `t_question` 做 Seq Scan，扫描 5225 行。
  - 试卷列表按 `subject_id + paper_type` 过滤时做 Seq Scan + Sort；当前只有 99 行所以很快，但没有可随数据增长扩展的组合索引。
  - 答题明细 `exam_paper_answer_id = ? order by item_order` 做 Seq Scan + Sort；当前扫描 142 行，未来答题记录增加后会放大。
  - 用户日志最近 10 条按 `user_id` 查做 Seq Scan + Sort；当前扫描 82 行，日志增长后会变成明显慢点。
  - 任务答题记录 `task_exam_id + create_user` 做 Seq Scan；当前只有 1 行，数据增长后应补索引。
  - 班级答卷列表和班级排行中的 `COALESCE(record.class_id, user.class_id)` 会触发 Join 后过滤；test branch 当前记录表 `class_id` 空值为 0，因此可以优先改成直接使用记录表 `class_id`。
- 结合用户反馈“智能训练现在用得不多”，智能训练随机抽题不作为第一优先级；它仍是明确风险，但放到列表/日志/班级查询之后处理。

## Web 页面实测结论

- 测试时间：2026-07-22。
- 测试范围：
  - 本地：`http://127.0.0.1:8000`，通过 `.env.neon-test` 启动后端。
  - 远端：`https://gesp-csp-quiz.randolph87.top`。
  - 老师端账号：`彬彬老师`，只测试老师权限可访问页面。
  - 学生端账号：`student`。
- 登录与页面跳转均通过真实 Chromium 浏览器执行；未发现接口失败、前端控制台错误或页面异常。
- 接口耗时观察：
  - 本地学生错题本 `/api/student/question/answer/wrongQuestionPage` 约 3284 ms，远端约 2682 ms，是当前最突出的慢接口。
  - 远端学生试卷中心 `/api/student/exam/paper/pageList` 约 1893 ms，考试记录列表/历史约 1200-1314 ms，班级排行相关接口约 870-1013 ms。
  - 远端老师端常见列表接口多在 1100-1432 ms；远端登录后 Dashboard 约 1306 ms。
  - 本地老师端答卷列表 `/api/admin/examPaperAnswer/page` 约 1633 ms，其余列表大多 400-900 ms。
- 资源加载观察：
  - 本地登录页冷加载：管理端约 638 ms，学生端约 842 ms。
  - 远端登录页冷加载：管理端约 4238 ms，学生端约 8370 ms。
  - 登录页静态资源体积并不大，抽样主资源约 150 KB；远端慢主要表现为多个 JS/CSS/SVG 小资源各自有 400-1000 ms 级等待。
  - 学生端登录页会加载百度统计，远端还会加载 Cloudflare RUM；这些第三方/边缘监测资源不会直接造成业务接口慢，但会拖长冷启动完成时间和干扰体感。
- 结论更新：
  - 用户体感慢不完全是数据库慢。当前更像是“远端冷启动/网络往返/静态资源请求延迟 + 个别接口查询或后端处理慢”的组合。
  - 第一优先级应调整为：错题本接口、远端静态资源缓存/压缩/第三方脚本、试卷/记录/排行接口链路。

## 结论

在“不引起功能变化”的约束下，第一阶段只做观测、静态资源交付优化、低风险索引和错题本等价 SQL 收窄；暂不改智能训练抽题算法，也不直接改班级排行/答卷列表的 `COALESCE` fallback 逻辑。test branch 当前数据量偏小，建议上线前再对 production 做只读 `EXPLAIN` 或在 test branch 构造放大数据验证。

## 零功能变化修改方案

本节是按“不能引起功能变化”重新收敛后的执行边界。这里的“零功能变化”指不改变业务规则、权限、接口 URL、请求参数、响应字段、响应字段含义、排序/分页语义、页面交互流程、登录行为、题目抽取规则和统计口径；只允许改变资源交付方式、数据库访问路径、等价 SQL 形态和观测能力。

### 可直接进入第一阶段的改动

1. 观测和基准脚本：
   - 增加或保留只读性能测量脚本，统一输出页面耗时、接口耗时、静态资源耗时、关键 SQL 执行计划和表规模。
   - 脚本只读取 `.env.neon-test`，不打印连接串、密码或 token，不写业务数据。
   - 影响范围仅限排查工具，不影响线上功能。
2. 静态资源交付：
   - 对 Vite 构建产物中的带 hash 静态资源启用长缓存，例如 `/admin/assets/*`、`/student/assets/*` 使用 `Cache-Control: public, max-age=31536000, immutable`。
   - `index.html`、接口响应和非 hash 入口文件保持不缓存或短缓存，避免发布后用户拿到旧入口。
   - 启用或确认 gzip/brotli 压缩、HTTP/2/3 和 Cloudflare 静态缓存命中；这些只改变传输方式，不改变页面内容。
3. 低风险数据库索引：
   - 只给已有查询条件和已有显式排序补组合索引，不改查询条件、不改返回字段、不改分页方式。
   - 第一批候选仍是题目列表、试卷列表、答题明细、任务答题记录、用户日志、登录/微信登录相关索引。
   - 上线前必须用 `EXPLAIN (ANALYZE, BUFFERS)` 证明命中索引，并用接口响应对比证明数据条数、顺序和字段一致。
4. 错题本等价 SQL 收窄：
   - `/api/student/question/answer/wrongQuestionPage` 本地和远端都慢，优先做查询链路定位。
   - 如果确认慢点在 SQL，可把内部 CTE 的 `select *` 收窄为最终计算所需字段，或拆出重复宽字段，减少排序/聚合宽度。
   - 响应 JSON、分页总数、错题去重规则、排序规则和错题历史含义必须逐项保持一致。
5. 浏览器加载顺序检查：
   - 只排查是否存在重复请求、串行等待或不必要的首屏阻塞。
   - 只有在确认重复请求的参数、响应和触发场景完全一致时，才允许去重；否则只记录问题，不修改。

### 不纳入零功能变化第一阶段的改动

- 智能训练抽题算法：即使性能收益明确，也可能改变随机分布、知识点覆盖或题目组合，按用户要求暂不作为当前主要优化点。
- 班级排行和答卷列表的 `COALESCE(record.class_id, user.class_id)` 直接改写：test branch 当前空 `class_id` 为 0，但生产和未来写入路径仍需确认；直接去掉 fallback 可能改变历史空值数据的归属。
- 用户名模糊搜索改前缀搜索、游标分页替换 offset 分页、限制筛选条件、改变默认排序：这些都会改变用户可见行为或边界，不进入本轮。
- 禁用百度统计或 Cloudflare RUM：会改变统计/观测行为；如果只做延迟加载，也要先确认统计口径是否允许变化。

### 零功能变化验收门槛

- API 对比：对错题本、学生试卷中心、考试记录、班级排行、管理端题目/试卷/答卷列表分别采集改前改后响应，比较状态码、字段结构、分页总数、当前页数量、关键排序字段和核心业务字段。
- 页面对比：用同一老师账号和学生账号跑真实浏览器路径，确认登录、列表、筛选、分页、详情跳转、错题本和排行榜可正常使用，且无控制台错误。
- SQL 对比：所有索引和等价 SQL 调整都要保留改前/改后 `EXPLAIN (ANALYZE, BUFFERS)`；只接受执行计划改善且结果一致的改动。
- 静态资源对比：确认 hash 静态资源可长缓存，`index.html` 不长缓存；远端冷加载和二次加载分别测量，不能出现发布后入口缓存风险。
- 回滚边界：每个数据库索引、配置项或 SQL 调整必须能单独回滚；如果某项回滚会影响其它项，不能合并上线。

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

1. 先固化可重复的页面/API/SQL 基准测量，确保改前改后可对比，并且脚本不暴露 `.env.neon-test` 中的敏感信息。
2. 优化远端静态资源交付：检查 gzip/brotli、Cache-Control、Cloudflare 缓存命中、HTTP/2/3 和多小文件加载；只对 hash 资源做长缓存，入口 HTML 不长缓存。
3. 第一批上线低风险索引：题目列表、试卷列表、答题明细、任务答题记录、用户日志、登录/微信登录；只覆盖已有条件和已有排序。
4. 排查并等价优化学生错题本接口 `/api/student/question/answer/wrongQuestionPage`：优先定位 SQL/后端处理/网络占比；若改 SQL，只做字段投影收窄或等价执行计划优化。
5. 在生产库做只读观测：表规模、空 `class_id` 数量、关键 SQL 的 `EXPLAIN (ANALYZE, BUFFERS)`，确认索引覆盖真实慢点。
6. 暂不执行 `COALESCE` fallback 改写、智能训练抽题算法调整、搜索语义变更、分页语义变更和统计脚本禁用；这些需要用户单独确认是否接受行为边界变化。

## 风险与待确认

- 待确认：线上延迟主要发生在哪些页面或操作，例如智能训练生成、错题本、答卷列表、班级排行、登录、管理端题目搜索。
- 待确认：production 和 test branch 当前数据量、空 `class_id` 历史数据规模、Neon 是否已启用 `pg_stat_statements`。
- 风险：新增索引会增加写入成本和存储占用；在生产大表上建索引应优先评估 `CREATE INDEX CONCURRENTLY`，但 Flyway 默认事务行为与并发建索引需要单独处理。
- 风险：智能训练抽题逻辑调整后，要保证知识点权重、最小题数、题目不重复和题型展示都不回归。
- 边界：只要会改变统计口径、历史空值 fallback、随机分布、搜索匹配方式、分页稳定性或用户可见加载顺序，就不纳入“零功能变化”第一阶段。

## 第一阶段实施记录

- 实施时间：2026-07-22。
- 静态资源交付：生产模式下 `/admin/static/**` 和 `/student/static/**` 在已有 365 天公开缓存基础上补充 `immutable`；`/admin/index.html`、`/student/index.html` 和兜底 `/**` 仍保持 0 秒缓存，避免入口 HTML 长缓存。
- 压缩配置：保留 `application.yml` 已启用的 gzip 压缩配置，未改变压缩 MIME 类型、API 内容或页面内容。
- 低风险索引迁移：新增 `V8__add_first_phase_query_performance_indexes.sql`，只使用 `CREATE INDEX IF NOT EXISTS` 新增普通/部分普通索引，覆盖题目列表、试卷列表、学生考试记录、管理端答卷按科目/班级过滤、答题明细、登录/微信登录、任务答题记录和用户日志查询；未改表字段、数据、约束或查询结果。
- 错题本等价 SQL 收窄：`studentWrongQuestionPage` 的 `wrong_answers` CTE 从 `select *` 收窄为后续分组、去重、展示和关联实际使用的 `id, question_id, question_type, subject_id, create_time`，保持 WHERE、去重、排序、分页和返回字段含义不变。
- 观测脚本：新增 `scripts/measure-query-performance.ps1`，默认从 `.env.neon-test` 读取连接串并隐藏连接详情，通过 `psql` 执行只读事务内的表规模、索引清单和关键 SQL `EXPLAIN (ANALYZE, BUFFERS)`；可选 `-BaseUrl` 测量入口 HTML 与首个 hash 静态资源的状态码、耗时、缓存头和压缩头。
- 本地验证：mapper XML 解析通过；V8 迁移静态检查确认只有 10 条 `CREATE INDEX IF NOT EXISTS`，无 `ALTER/UPDATE/INSERT/DELETE/DROP/TRUNCATE`；`scripts/measure-query-performance.ps1 -SkipSql -SkipHttp` 语法执行通过；使用项目内 Maven wrapper 执行 `mvnw.cmd -q -DskipTests compile` 通过。
- 验证限制：当前环境未安装 `psql` 到 PATH，未执行 test branch 的 `EXPLAIN`；未启动完整本地服务做 HTTP 头实测；未连接 production。
- 明确未做：未修改智能训练抽题算法；未修改班级排行或答卷列表的 `COALESCE` fallback；未禁用或延迟百度统计、Cloudflare RUM；未改变前端交互、接口字段、排序或分页语义。

## 第一阶段独立验证记录

- 验证时间：2026-07-22。
- 验证方式：由独立验证 subagent 读取实际 diff 后启动本地 Neon test 服务，用真实 Chromium 登录本地和远端学生端、老师端，对关键只读 API 做 3 次探针取中位数，并启动临时生产静态模式实例验证缓存头。
- 验证结论：修改基本满足“零功能变化”边界；V8 迁移只包含 10 条 `CREATE INDEX IF NOT EXISTS`；错题本 SQL 只收窄 CTE 投影字段；入口 `index.html` 为 `no-store`，抽样 hash JS/CSS 为 `public, max-age=31536000, immutable`。
- 性能对比：

| 页面/接口 | 改前基线 | 改后本地候选 | 远端现状 | 变化结论 |
|---|---:|---:|---:|---|
| 学生登录页冷加载 | 本地约 842 ms；远端约 8370 ms | 774 ms | 4625 ms | 本地小幅改善；远端较基线改善但仍慢于本地 |
| 学生登录提交 `/api/student/auth/login` | 未单列 | 374 ms | 827 ms | 可用；远端约为本地 2.2 倍 |
| 学生错题本 `/api/student/question/answer/wrongQuestionPage` | 本地约 3284 ms；远端约 2682 ms | 2292 ms | 2873 ms | 本地约快 30%；远端需部署候选后复测 |
| 学生试卷中心 `/api/student/exam/paper/pageList` | 远端约 1893 ms | 376 ms | 1992 ms | 本地很快；远端与基线接近略慢 |
| 学生考试记录 `/api/student/exampaper/answer/pageList` | 远端记录/历史约 1200-1314 ms | 645 ms | 1640 ms | 本地可接受；远端现状较基线慢 |
| 学生班级排行 `/api/student/dashboard/class/ranking` | 远端约 870-1013 ms | 368 ms | 1409 ms | 本地快；远端现状较基线慢 |
| 老师登录页冷加载 | 本地约 638 ms；远端约 4238 ms | 671 ms | 3212 ms | 本地基本持平；远端较基线改善 |
| 老师登录提交 `/api/admin/auth/login` | 未单列 | 371 ms | 1889 ms | 本地正常；远端登录 API 偏慢 |
| 老师 Dashboard `/api/admin/dashboard/index` | 远端约 1306 ms | 763 ms | 1945 ms | 本地快于远端；远端现状较基线慢 |
| 老师题目列表 `/api/admin/question/page` | 远端常见列表约 1100-1432 ms；本地其它列表多为 400-900 ms | 1329 ms | 3291 ms | 本地仍偏高；远端明显偏慢 |
| 老师试卷列表 `/api/admin/exam/paper/page` | 远端常见列表约 1100-1432 ms | 389 ms | 1435 ms | 本地明显快；远端接近基线上沿 |
| 老师答卷列表 `/api/admin/examPaperAnswer/page` | 本地约 1633 ms；远端常见列表约 1100-1432 ms | 1420 ms | 3412 ms | 本地约快 13%；远端需部署候选后复测 |

- 验证限制：本机没有 `psql`，未跑 SQL `EXPLAIN (ANALYZE, BUFFERS)`；远端仍是现状版本，不代表候选部署后的远端效果。

## Fly 与树莓派部署后对比记录

- 测试时间：2026-07-22。
- 部署版本：`393b4a29` 镜像已推送到 ACR，并分别部署到 Fly 测试端和树莓派生产端。
- 测试口径：页面首屏使用真实 Chromium 的 `load` 完成时间；接口使用登录后连续 3 次请求的中位数。
- 环境差异：Fly 连接 Neon test branch，树莓派连接 Neon production branch，部分接口数据量不同，因此该表用于判断远端链路体感差异，不作为严格数据库同库压测。

| 页面/接口 | Fly 测试端 | 树莓派生产端部署后 | 树莓派部署前 | 结论 |
|---|---:|---:|---:|---|
| 学生登录页首屏 | 1652 ms | 3091 ms | 未同口径采集 | 树莓派公网首屏约为 Fly 1.9 倍 |
| 老师登录页首屏 | 2127 ms | 2073 ms | 未同口径采集 | 两端接近 |
| 学生登录 `/api/student/auth/login` | 733 ms | 2431 ms | 996 ms | 树莓派本轮登录抖动偏大，较部署前慢 |
| 学生错题本 `/api/student/question/answer/wrongQuestionPage` | 2587 ms | 2683 ms | 3111 ms | 树莓派较部署前约快 14%，与 Fly 接近 |
| 学生试卷中心 `/api/student/exam/paper/pageList` | 739 ms | 771 ms | 1058 ms | 树莓派较部署前约快 27%，与 Fly 接近 |
| 学生考试记录 `/api/student/exampaper/answer/pageList` | 946 ms | 1423 ms | 1168 ms | 树莓派较 Fly 慢，且本轮较部署前慢 |
| 学生班级排行 `/api/student/dashboard/class/ranking` | 742 ms | 932 ms | 1213 ms | 树莓派较部署前约快 23% |
| 老师登录 `/api/admin/auth/login` | 860 ms | 966 ms | 882 ms | 两端接近，树莓派略慢 |
| 老师 Dashboard `/api/admin/dashboard/index` | 1094 ms | 1284 ms | 1421 ms | 树莓派较部署前约快 10% |
| 老师题目列表 `/api/admin/question/page` | 2386 ms | 1782 ms | 2189 ms | 树莓派较部署前约快 19%，且快于 Fly |
| 老师试卷列表 `/api/admin/exam/paper/page` | 848 ms | 1001 ms | 1616 ms | 树莓派较部署前约快 38% |
| 老师答卷列表 `/api/admin/examPaperAnswer/page` | 1501 ms | 2052 ms | 2057 ms | 树莓派基本无变化，仍慢于 Fly |

- 静态缓存头验证：
  - Fly 公网：`/admin/static/**`、`/student/static/**` 返回 `public, max-age=31536000, immutable`。
  - 树莓派本机 `127.0.0.1:8000`：应用同样返回 `public, max-age=31536000, immutable`。
  - 树莓派公网域名：代理层返回 `public, max-age=31536000`，缺少 `immutable`；说明应用变更已生效，但公网代理层覆盖或重写了该头。
- 部署后结论：
  - 这次零功能变化优化对树莓派的题目列表、试卷列表、错题本、班级排行有可见收益。
  - 登录、考试记录和答卷列表仍有网络抖动或后端链路慢点，不能只归因于数据库索引。
  - 若继续保持零功能变化，下一步应优先处理树莓派公网代理缓存头传递、登录链路耗时拆分，以及答卷列表/考试记录的生产只读执行计划。

## 收尾记录

- 完成状态：
- 归档日期：
- 归档原因：
