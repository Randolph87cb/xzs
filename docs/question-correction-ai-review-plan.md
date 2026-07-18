# 错题改正与 AI 审核修改方案

## 背景与现状

- 已确认教师端错题审核入口在 `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`，接口在 `source/xzs/src/main/java/com/mindskip/xzs/controller/admin/QuestionCorrectionController.java`。
- 已确认学生错题本入口在 `frontend/apps/student/src/views/question/QuestionErrorView.vue`，题目详情接口在 `source/xzs/src/main/java/com/mindskip/xzs/controller/student/QuestionAnswerController.java`，改错提交接口在 `source/xzs/src/main/java/com/mindskip/xzs/controller/student/QuestionCorrectionController.java`。
- 已确认学生端 `QuestionReview` 已展示题面、选项、作答结果、解析和正确答案；数据来自 `questionService.getQuestionEditRequestVM(...)`，其中会填充 `analyze`、`correct`、`correctArray`。
- 已确认教师端错题审核 SQL 当前返回题干、选项、学生答案和正确答案，但未返回解析字段。
- 已确认用户资料入口已有 `/api/admin/user/current` 和 `/api/admin/user/update`，前端页面在 `frontend/apps/admin/src/views/profile/ProfileView.vue`。当前用户表和 `UserMapper` 没有大模型配置字段，也没有现成大模型调用能力。

## 结论

推荐先抽一个跨教师端和学生端复用的“错题上下文展示组件”，补齐教师审核接口的解析字段；再新增教师级 AI 审核配置和“学生提交后自动 AI 预审”能力。AI 预审结果只保存为建议记录，老师打开审核详情时直接看到结果并可预填审核表单，但最终通过/驳回必须由老师确认保存。

## 已确认约束

- AI 审核不允许自动通过或自动驳回，只能生成预审建议；`t_question_correction_record.review_status` 只能由老师人工保存审核时更新。
- 大模型接口固定按 OpenAI-compatible Chat Completions 模式接入。
- 自动预审使用错题所属班级的负责老师配置执行；负责老师未配置或配置不可用时，记录为 AI 预审跳过或失败，不影响学生提交。

## 需求拆解

### 1. 老师错题审核时能看到解析

- 当前现状：
  - 教师端审核弹窗已经显示题干、选项、学生答案、正确答案。
  - 后端 `pageBaseSql()` 从 `t_text_content.content` 中取了 `titleContent` 和 `questionItemObjects`，没有取 `analyze`。
- 判断：
  - 不需要新增题库字段；解析已经在 `t_text_content.content` JSON 中。
  - 只需要接口加字段、前端类型加字段、审核弹窗渲染解析。
- 修改方案：
  - 后端在 `QuestionCorrectionController.pageBaseSql()` 增加：
    - `tc.content::jsonb ->> 'analyze' as analyze`
  - 前端 `AdminQuestionCorrectionItem` 增加 `analyze?: string`。
  - 教师审核弹窗题目区域增加“解析”展示，使用现有 `QuestionMarkdown`。
  - 如果解析为空，展示“暂无解析”，避免空白区域误以为加载失败。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/admin/QuestionCorrectionController.java`
  - `frontend/packages/api-client/src/adminOperations.ts`
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
- 验证方案：
  - 构造一条含解析的错题改正记录，调用 `/api/admin/questionCorrection/select/{id}`，确认响应包含 `analyze`。
  - 教师登录进入“改错审核”，打开审核弹窗，确认题干、选项、学生答案、正确答案、解析均可见。
  - 对解析为空的题目做一次烟测，确认页面不报错。

### 2. 学生错题改正时能看到题面、解析、自己的选项和正确选项，并和老师审核共用部分界面

- 当前现状：
  - 学生端错题本右侧已经通过 `QuestionReview` 显示题目详情。
  - `QuestionReview` 当前会用禁用控件展示学生作答，并显示“解析”和“正确答案”。
  - 教师端审核弹窗使用另一套局部模板和 `formatAnswer/normalizeQuestionItems` 逻辑，存在重复。
- 判断：
  - 学生端已具备核心数据，不应新增重复接口。
  - 需要把“题面、选项、我的答案、正确答案、解析”的展示抽成可复用组件，教师端和学生端统一使用，减少后续样式和答案格式分歧。
- 修改方案：
  - 在共享前端包中新增一个不依赖业务页面状态的题目上下文组件，例如：
    - `frontend/packages/question-renderer/src/QuestionCorrectionContext.vue`
  - 组件 props 建议：
    - `question`: 题目对象，包含 `title/questionType/items/analyze/correct/correctArray`。
    - `answer`: 学生答案对象，包含 `content/contentArray/doRight/score`。
    - `mode`: `student` 或 `review`，控制是否显示结果标签、分数等辅助信息。
  - 将学生端 `QuestionReview` 中已成熟的单选、多选、判断、填空、简答展示逻辑迁移到共享组件，保留 Element Plus 依赖时需把 `element-plus` 加为该包的 peer dependency 或改为纯 HTML 展示。推荐先采用纯展示组件，避免共享包引入 UI 框架强耦合。
  - 学生端 `QuestionErrorView.vue` 改为使用共享组件；改错表单仍放在学生端页面中。
  - 教师端 `QuestionCorrectionReviewView.vue` 将后端返回的 `title/items/correct/student_answer/analyze/question_type` 适配为共享组件需要的 `question/answer` 结构，替换当前局部题目展示模板。
  - 将当前教师端的 `formatAnswer`、`normalizeQuestionItems` 和学生端的 `dedupeQuestionItemsByPrefix` 归并为共享工具，减少一题多选、判断题中文内容映射不一致的问题。
- 影响范围：
  - `frontend/packages/question-renderer/src/index.ts`
  - `frontend/packages/question-renderer/src/QuestionCorrectionContext.vue`
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - `frontend/apps/student/src/components/QuestionReview.vue`
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
  - `frontend/packages/api-client/src/adminOperations.ts`
- 验证方案：
  - 学生端：错题本选择一条错题，确认题面、选项、自己的答案、正确答案、解析都在改错区域附近可见；单选、多选、判断至少各验一题。
  - 教师端：审核同一条错题，确认看到与学生端一致的题目上下文和解析。
  - 前端构建：执行 `pnpm --dir frontend -r build` 或项目已有等价构建命令。
  - 组件测试：补充 `question-renderer` 针对答案格式化和选项去重的单元测试。

### 3. 老师配置大模型 API，学生提交后自动跑 AI 预审，老师审核时直接展示

- 当前现状：
  - 管理端个人资料页可保存基础资料，但没有 AI 配置。
  - `t_user` 没有 AI 配置字段，`UserMapper` 是显式列映射，直接扩用户表需要同步较多映射。
  - 项目中未发现现成的大模型服务封装。
  - 学生提交改错的事务入口是 `/api/student/question/correction/submit`；现有逻辑只写入或更新 `t_question_correction_record`，没有提交后任务。
  - 项目已有 `ApplicationEventPublisher` 使用方式，但未发现现成 `@Async` 或事务提交后回调模式。
- 判断：
  - API key 属于敏感信息，不建议明文返回前端。
  - “保存到老师的数据中”可以通过以 `teacher_user_id` 为唯一键的一对一配置表实现，比直接扩 `t_user` 更低耦合，也便于后续增加不同 provider 参数。
  - AI 调用不应放在学生提交事务内同步执行；大模型接口慢、超时或失败时，不应影响学生提交成功。
  - 老师审核要节省时间，应在审核列表或审核详情中展示“AI 预审状态”和最新建议，而不是要求老师手动点击触发。
  - AI 预审只能产生建议，不能直接写入最终审核状态；老师仍是最终审核动作的执行人。
- 修改方案：
  - 新增 Flyway 迁移 `V4__add_teacher_ai_review_config.sql`，创建表 `t_teacher_ai_review_config`：
    - `id serial primary key`
    - `teacher_user_id int4 not null unique`
    - `provider varchar(32) not null default 'openai_compatible'`
    - `base_url varchar(512) not null`
    - `model varchar(128) not null`
    - `api_key_cipher text`
    - `enabled bool not null default true`
    - `prompt text`
    - `create_time timestamp(6)`
    - `modify_time timestamp(6)`
  - 同一个迁移或后续迁移中新增 AI 预审记录表 `t_question_correction_ai_review_record`：
    - `id serial primary key`
    - `correction_id int4 not null`
    - `teacher_user_id int4`
    - `trigger_type varchar(32) not null default 'AUTO_SUBMIT'`
    - `status varchar(32) not null`，取值建议为 `PENDING/RUNNING/SUCCESS/FAILED/SKIPPED`
    - `review_result varchar(32)`，取值建议为 `APPROVED/REJECTED/UNCERTAIN`
    - `review_comment text`
    - `confidence numeric(5, 4)`
    - `reason text`
    - `raw_content text`
    - `error_message text`
    - `request_time timestamp(6)`
    - `finish_time timestamp(6)`
    - `create_time timestamp(6)`
    - 索引：`(correction_id, create_time desc)`，便于审核详情取最新一条。
  - API key 存储：
    - 后端用服务端环境变量提供加密密钥，例如 `XZS_AI_CONFIG_SECRET`。
    - 保存时加密 `apiKey`；查询配置时只返回 `hasApiKey: true/false`，不返回明文 key。
    - 前端保存时如果 key 输入为空，则保留旧 key；勾选“清除密钥”时后端置空。
  - 后端新增配置接口，建议放在错题审核域下：
    - `POST /api/admin/questionCorrection/ai/config/select`
    - `POST /api/admin/questionCorrection/ai/config/edit`
    - 仅角色为老师或管理员可访问；老师只能读写自己的配置，管理员可按后续需要扩展。
  - 后端新增自动预审服务：
    - 在学生提交新改错或被驳回后重新提交时，先完成 `t_question_correction_record` 写入或更新。
    - 事务提交后触发 AI 预审任务，推荐使用 `TransactionSynchronizationManager.registerSynchronization(... afterCommit ...)` 或 `@TransactionalEventListener(phase = AFTER_COMMIT)`。
    - 预审任务根据错题所属班级找到负责老师；只使用负责老师且 `enabled = true` 的 AI 配置。若找不到负责老师、负责老师未配置或配置不可用，写入 `SKIPPED` 或 `FAILED` 记录，并说明原因。
    - 任务先插入 `PENDING/RUNNING` 记录，再组装题干、选项、解析、学生答案、正确答案、学生错误原因、学生正确思路、历史审核意见，调用 OpenAI-compatible Chat Completions 接口。
    - 成功后把 `reviewResult/reviewComment/confidence/reason/rawContent` 写入 AI 预审记录；失败后写入 `FAILED/error_message`，不修改学生改错记录的 `review_status`。
    - 为避免重复触发，提交或重新提交同一 `correction_id` 时只保留最新建议为展示依据；可以允许多条历史记录，但详情接口按 `create_time desc, id desc limit 1` 取最新。
  - 后端审核查询接口扩展：
    - `/api/admin/questionCorrection/page` 返回 `ai_review_status`、`ai_review_result`、`ai_review_confidence`、`ai_review_time`，便于老师在列表上优先处理。
    - `/api/admin/questionCorrection/select/{id}` 返回 `aiReview` 对象，包含最新 AI 预审状态、建议结果、建议意见、理由、置信度、错误信息和完成时间。
    - 仍复用 `correctionScopeSql(...)` 校验老师只能看到自己班级范围内的 AI 预审结果。
  - 可选保留手动重跑接口：
    - `POST /api/admin/questionCorrection/ai/retry`
    - 入参：`correctionId`
    - 仅用于 AI 失败、老师修改配置后补跑、或希望刷新建议的场景；不是主流程按钮。
  - 教师端页面：
    - 在个人资料页增加“AI 审核配置”区域，仅老师角色优先显示，管理员可显示但标注适用于老师审核。
    - 在改错审核列表增加 AI 状态列：未配置、预审中、建议通过、建议驳回、不确定、失败。
    - 在改错审核弹窗顶部展示最新 AI 预审卡片，包括建议结果、建议意见、理由、置信度和失败原因。
    - AI 结果为 `APPROVED/REJECTED` 时，只自动预填现有审核表单；老师必须点击“保存审核”才会更新最终审核状态，也可以修改审核意见后保存。
    - 若 AI 状态为 `PENDING/RUNNING`，页面展示“AI 预审中”，可通过刷新详情获取最新结果。
    - 若未配置或失败，直接展示原因；可提供“去配置”或“重跑 AI 预审”入口，但不作为常规审核必点步骤。
  - 审核记录：
    - 最终保存仍走现有 `/review/edit`，`reviewer_id/reviewer_name` 仍是老师。
    - 人工审核历史 `t_question_correction_review_record` 不直接混入 AI 原始建议；AI 建议保存在 `t_question_correction_ai_review_record`，便于区分“机器建议”和“老师最终审核”。
- 影响范围：
  - `source/xzs/src/main/resources/db/migration/V4__add_teacher_ai_review_config.sql`
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/admin/QuestionCorrectionController.java` 或拆出 `QuestionCorrectionAiController`
  - 新增 `TeacherAiReviewConfig` domain/service/repository 或在初期沿用 `JdbcTemplate`
  - 新增 AI client/service，例如 `QuestionCorrectionAiReviewService`
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/student/QuestionCorrectionController.java`
  - 新增提交后事件、监听器或事务 afterCommit 任务，例如 `QuestionCorrectionSubmittedEvent`、`QuestionCorrectionAiReviewListener`
  - `frontend/apps/admin/src/views/profile/ProfileView.vue`
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
  - `frontend/packages/api-client/src/adminOperations.ts`
- 验证方案：
  - 数据库：启动后确认 Flyway 应用到 V4，`t_teacher_ai_review_config` 存在，`teacher_user_id` 唯一约束生效。
  - 配置接口：老师保存 baseUrl/model/apiKey 后，再查询只返回 `hasApiKey`，不返回明文；空 key 更新不覆盖旧 key。
  - 权限：老师 A 不能对老师 B 班级错题调用 AI 审核；学生不能访问配置和 AI 审核接口。
  - 自动触发：学生提交新改错后，提交接口快速返回成功，事务提交后生成 AI 预审记录；重新提交被驳回记录时生成新的 AI 预审记录。
  - 失败隔离：mock 大模型超时或返回错误时，学生提交仍成功，AI 记录变为 `FAILED`，审核详情展示失败原因。
  - AI 审核：使用一个 OpenAI-compatible mock 服务或本地 stub，确认请求内容包含题干、解析、学生答案、正确答案、学生改错内容；响应能保存到 AI 预审记录。
  - 老师审核：打开审核列表可看到 AI 状态；打开详情能直接看到 AI 建议并预填审核表单。
  - 人工确认：AI 建议生成后不点“保存审核”时 `t_question_correction_record.review_status` 仍为 `SUBMITTED`；点击保存后才更新最终审核状态和人工审核历史。

## 执行顺序

1. 先补教师端解析字段和展示，完成需求 1。
2. 抽共享题目上下文组件，并替换教师审核弹窗和学生错题详情，完成需求 2。
3. 增加 AI 配置表、配置接口和个人资料页配置区域。
4. 增加 AI 预审记录表、提交后自动触发任务和 AI 调用服务。
5. 扩展教师审核列表和详情，直接展示最新 AI 预审结果并预填审核表单。
6. 补充测试与手工验收。

## 风险与待确认

- API key 加密密钥来源：需要部署环境提供 `XZS_AI_CONFIG_SECRET`。没有该密钥时应禁止保存 key，不能降级明文存储。
- 是否记录 AI 原文：建议记录，但要避免把 API key、学生隐私或过长 prompt 写入日志。
- 负责老师配置缺失：自动预审应记录为 `SKIPPED` 或 `FAILED`，不能阻断学生提交，也不能影响老师后续人工审核。
- AI 预审任务执行器：需要设置超时、重试次数和并发上限，避免大量学生同时提交时耗尽后端线程或大模型额度。
