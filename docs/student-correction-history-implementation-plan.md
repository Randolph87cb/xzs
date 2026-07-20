# 学生错题与历史成绩改造方案

## 背景与现状

- 错题审核意见、学生改错内容和 AI 建议目前都以普通文本展示，无法渲染 Markdown、公式和代码块。
- 项目已有 `@xzs/question-renderer` 的 `QuestionMarkdown` 组件，支持 Markdown、KaTeX 公式、代码高亮，并通过 DOMPurify 清洗渲染结果。
- 学生个人中心目前只支持修改昵称；后端已有 `AuthenticationService` 的旧密码校验、密码编码和解码能力。
- 答卷主表 `t_exam_paper_answer` 已按每次作答记录 `exam_paper_id`、分数、用时、正确题数和提交时间。
- 单题作答表 `t_exam_paper_question_customer_answer` 已按每次作答记录 `question_id`、`exam_paper_id`、`do_right`、学生和提交时间。
- 题目表 `t_question` 已有 `knowledge_point` 字段。
- 当前任务卷提交逻辑禁止同一任务中的同一试卷重复作答；需要调整为允许重复提交，但任务完成状态仍可指向最新一次答卷。

## 结论

按 `exam_paper_id` 定义同一套卷子，任务卷也纳入同一套卷子的历史分数；错题本从“每次错误一行”改为“每道题一行”的聚合视图；老师审核意见、学生改错内容和 AI 建议统一使用 Markdown/公式渲染。

## Harness 启动结构

### 目标

稳定完成以下用户可见能力：

1. 错题审核相关文本统一支持 Markdown、公式和代码块展示。
2. 学生可以在个人中心自行修改密码。
3. 同一 `exam_paper_id` 的所有历史分数可查看，包含任务卷。
4. 错题本按题目聚合，显示同题错误次数，并支持按知识点分组排序，组内错误次数多的题排前面。

### 适用范围

- 适用于本次学生端错题、历史成绩、学生账号能力和改错审核展示改造。
- 不适用于重构整套考试系统、替换鉴权机制、改造管理端用户体系或引入新的统计服务。

### 输入

- 用户确认：同一套卷子按 `exam_paper_id` 区分，任务卷也归入同一套卷子。
- 用户确认：错题本使用每道题一行的聚合视图。
- 用户确认：Markdown 覆盖老师审核意见、学生改错内容和 AI 建议。
- 已查看的事实来源：后端 controller/service/mapper、前端学生端/管理端页面、`question-renderer`、Flyway baseline schema。

### 执行流程

1. 主线程落成本方案文档。
2. 实现 subagent 执行功能修改：
   - 后端接口、VM、mapper、迁移脚本和测试；
   - 学生端与管理端前端页面、API client 类型和调用；
   - 不执行 Git 操作。
3. 验证 subagent 独立读取实现结果：
   - 运行后端测试、前端类型检查/构建、关键单测；
   - 检查关键页面和接口行为；
   - 不执行 Git 操作。
4. 主线程复核 subagent 汇报和工作区 diff。
5. 主线程按项目规则执行 Git add、commit、push。

### 角色分工

- 主线程：写方案、拆任务、创建 subagent、验收结果、处理 Git。
- 实现 subagent：只负责代码、迁移和测试文件改动。
- 验证 subagent：只负责独立验证，不修改功能代码；必要时可新增或修正测试，但需汇报。
- 人工：确认产品边界或阻塞事项。

### 检查点

- 方案文档存在且包含 harness 启动结构。
- 实现 subagent 汇报修改文件、功能覆盖和未完成事项。
- 验证 subagent 汇报真实执行过的命令、结果和未覆盖风险。
- 主线程复核 diff 与需求一致，且没有无关改动。

### 产出

- 本方案文档。
- 后端接口、测试和必要数据库迁移。
- 学生端、管理端前端改动。
- 验证结果摘要。
- Git commit 和 push。

### 失败处理

- 信息不足：主线程暂停并向用户确认。
- 实现失败：实现 subagent 汇报阻塞，主线程评估是否缩小范围或补充说明。
- 验证失败：优先让实现 subagent 根据验证反馈修复，再由验证 subagent 复验。
- 数据迁移风险：不删除历史数据；只新增兼容索引或字段，避免破坏生产 Neon 数据。

### Git 策略

- subagent 不执行 Git 操作。
- 主线程最终执行 `git status`、`git add`、`git commit`、`git push`。
- 提交信息默认使用中文。

## 需求拆解

### 1. Markdown 和公式统一渲染

- 当前现状：
  - 学生错题本中 `review_comment`、学生错误原因、学生正确思路使用普通文本插值。
  - 管理端改错审核页中学生提交内容、AI 建议、审核历史意见使用普通文本或表格文本列。
  - `QuestionMarkdown` 已支持 Markdown、KaTeX 公式、代码高亮和 DOMPurify 清洗。
- 判断：
  - 不需要新增渲染库，直接复用 `@xzs/question-renderer`。
  - 老师、学生和 AI 文本都可能包含公式，展示态应统一渲染。
- 修改方案：
  - 学生端 `QuestionErrorView.vue`：老师驳回意见、历史审核意见、学生错误原因、学生正确思路全部改用 `QuestionMarkdown` 展示。
  - 管理端 `QuestionCorrectionReviewView.vue`：学生提交内容、AI 给老师看的理由、AI 返回给学生的建议、审核历史意见改用 `QuestionMarkdown` 展示。
  - 审核意见输入仍使用 textarea，并增加 Markdown 预览，避免编辑体验变重。
  - 保持 `QuestionMarkdown` 的清洗逻辑；必要时补渲染测试覆盖学生/AI 文本。
- 影响范围：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
  - `frontend/packages/question-renderer/src/render.test.ts`
- 验证方案：
  - 用包含 `**重点**`、`$a^2+b^2=c^2$`、代码块和 HTML 的文本验证展示。
  - 运行 `pnpm --dir frontend test:question-renderer`。
  - 运行学生端和管理端类型检查或构建。

### 2. 学生自助修改密码

- 当前现状：
  - 学生资料接口只更新昵称。
  - 后端已注入 `AuthenticationService`，可校验旧密码并编码新密码。
  - 前端个人中心已有资料表单，可以增加改密区域。
- 判断：
  - 不需要新增数据库表。
  - 改密后保留当前会话，避免额外改造 token 全量失效逻辑。
- 修改方案：
  - 新增 `StudentChangePasswordVM`，字段为 `oldPassword`、`newPassword`、`confirmPassword`。
  - 新增 `POST /api/student/user/password/change`。
  - 后端校验旧密码正确、新密码非空、长度合理、两次输入一致。
  - 使用 `authenticationService.pwdEncode(newPassword)` 更新当前用户密码。
  - 写入用户事件日志。
  - 学生端个人中心增加“修改密码”表单，提交成功后清空输入。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/UserController.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/viewmodel/student/user/StudentChangePasswordVM.java`
  - `source/xzs/src/test/java/com/mindskip/xzs/controller/student/UserControllerTest.java`
  - `frontend/packages/api-client/src/studentUser.ts`
  - `frontend/apps/student/src/views/user/UserCenterView.vue`
- 验证方案：
  - 后端测试覆盖旧密码错误、新密码不一致、修改成功。
  - 手工或浏览器级验证：旧密码无法登录，新密码可登录。

### 3. 同一套卷子历史分数

- 当前现状：
  - `t_exam_paper_answer` 已有每次答卷记录。
  - 普通/智能训练卷可产生多次记录。
  - 任务卷当前被 `taskPaperAnswered` 阻止重复提交。
  - `t_task_exam_customer_answer` 对同一任务内同一试卷只保留一个 `examPaperAnswerId`。
- 判断：
  - 历史分数应以 `create_user + exam_paper_id` 聚合，包含所有任务卷和非任务卷。
  - 任务完成状态可以继续指向最新答卷；完整历史从 `t_exam_paper_answer` 查询。
- 修改方案：
  - 移除或调整任务卷重复提交限制，不再因为同一任务中的同一 `exam_paper_id` 已作答而拒绝提交。
  - 保持 `TaskExamCustomerAnswerService.insertOrUpdate` 的最新答卷覆盖行为，用于任务列表状态。
  - 新增学生接口 `POST /api/student/exampaper/answer/paperHistory/{paperId}`。
  - 返回同一 `exam_paper_id` 下当前学生的所有历史作答，并汇总 `attemptCount`、`bestScore`、`latestScore`、`averageScore`。
  - 学生考试记录页增加同卷历史入口或详情区。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/service/impl/ExamPaperAnswerServiceImpl.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/ExamPaperAnswerController.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/viewmodel/student/exampaper/*`
  - `source/xzs/src/main/resources/mapper/ExamPaperAnswerMapper.xml`
  - `frontend/packages/api-client/src/studentExam.ts`
  - `frontend/apps/student/src/views/record/RecordListView.vue`
- 验证方案：
  - 构造同一 `exam_paper_id` 的普通卷和任务卷多次答题记录，历史接口返回同一分组。
  - 任务卷重复提交不再返回“试卷不能重复做”。
  - 任务列表仍显示最新一次状态。

### 4. 错题本按题目聚合、错误次数和知识点排序

- 当前现状：
  - 错题本接口按 `t_exam_paper_question_customer_answer` 错误明细分页，一次错误一行。
  - 题目知识点已存在于 `t_question.knowledge_point`。
  - 错题改错记录绑定 `customer_answer_id`。
- 判断：
  - 错题本主列表应聚合到 `question_id` 级别。
  - 改错记录继续绑定具体最近一次错误明细，兼容现有审核流程。
- 修改方案：
  - 新增学生错题聚合接口，例如 `POST /api/student/question/answer/wrongQuestionPage`。
  - 每行返回 `questionId`、`latestCustomerAnswerId`、`shortTitle`、`subjectName`、`knowledgePoint`、`wrongCount`、`latestWrongTime`、`correctionStatus`。
  - 默认排序：`knowledgePoint asc`、`wrongCount desc`、`latestWrongTime desc`。
  - 前端错题本左侧列表改为知识点分组，每道题一行，展示错误次数。
  - 选中聚合行后，用 `latestCustomerAnswerId` 加载题目上下文和最近一次改错记录。
  - 详情侧展示同题历史错误记录：时间、试卷、得分、改错状态和审核意见。
  - 新增必要索引：
    - `t_exam_paper_answer(create_user, exam_paper_id, create_time desc)`
    - `t_exam_paper_question_customer_answer(create_user, question_id, create_time desc) where do_right = false`
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/QuestionAnswerController.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/viewmodel/student/question/answer/*`
  - `source/xzs/src/main/resources/mapper/ExamPaperQuestionCustomerAnswerMapper.xml`
  - `source/xzs/src/main/resources/db/migration/V*_*.sql`
  - `frontend/packages/api-client/src/studentExam.ts`
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
- 验证方案：
  - 同一题错 3 次只显示一行，错误次数为 3。
  - 不同知识点按知识点分组；同组内错误次数高的排前面。
  - 最近一次错误仍能提交改错、查看审核意见和历史记录。

## 执行顺序

1. 后端接口与迁移：改任务卷重复提交，新增历史分数接口、错题聚合接口、索引。
2. 后端测试：覆盖改密、历史成绩、错题聚合和任务卷重复提交。
3. 前端 API client 类型和调用。
4. 学生端考试记录页和错题本改造。
5. 管理端/学生端 Markdown 展示改造。
6. 独立验证：后端测试、前端类型检查、构建和页面烟测。

## 风险与边界

- 任务卷允许重复提交后，任务完成状态仍指向最新一次答卷；历史列表按 `exam_paper_id` 查完整记录。
- 错题改错记录仍绑定 `customer_answer_id`，不是题目级审核记录。
- Markdown 渲染复用 DOMPurify 清洗；不要直接使用 `v-html` 渲染未清洗文本。
- 不回填冗余统计表，先用实时聚合和索引满足需求。
