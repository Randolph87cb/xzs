# 改错审核与学生错题本布局优化方案

## 背景与现状

- 管理端改错审核页在 `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`。
- 学生端错题本页在 `frontend/apps/student/src/views/question/QuestionErrorView.vue`。
- 两端都已经使用 `@xzs/question-renderer` 的 `QuestionCorrectionContext` 展示题目上下文，题面、选项、解析、学生答案和正确答案的基础展示能力可以继续复用。
- 管理端外层菜单在 `frontend/apps/admin/src/layouts/AdminLayout.vue` 中固定为 `232px`，当前没有收起状态；在宽屏下仍占用较多横向空间。
- 管理端审核页当前主布局为：队列 `280-330px` + 工作区；工作区内部再分为题目上下文和右侧处理栏。右侧栏最小约 `320px`，审核处理、AI 预审、学生改错、历史纵向堆叠，导致 AI 建议和审核意见需要滚动才能看全。
- 学生端错题本当前主布局为：队列 `280-320px` + 题目上下文 + 右侧改错栏；在 1440px 左右宽度下，队列占比偏大，主要操作区相对被压缩。
- 当前 AI 预审返回给前端的结构只有 `reviewResult`、`reviewComment`、`reason`、`confidence` 等字段。要稳定拆成“给老师看的理由”和“返回给学生的理由”，需要后端 prompt、解析逻辑、数据表和前端类型一起扩展。

## 结论

推荐按“先释放横向空间，再把审核动作前置，再结构化 AI 输出”的顺序改造：管理端先增加左侧菜单收起能力，将审核队列压缩为窄队列，右侧改成固定操作栏；AI 预审成功后自动把建议结果和意见填入审核表单，但老师仍可修改确认。学生端保持同样的三栏工作台，但队列更窄、提交区置顶，老师意见常驻可见。

## 需求拆解

### 1. 管理端左侧主菜单可收起

- 当前现状：
  - `AdminLayout.vue` 中 `el-aside` 固定 `232px`。
  - 菜单项始终显示图标和文字，没有折叠按钮。
- 判断：
  - 这是当前审核页横向空间不足的第一层原因。宽屏下收起到图标栏可以释放约 `168px`。
- 修改方案：
  - 在 `AdminLayout.vue` 增加 `isAsideCollapsed` 状态。
  - `el-aside` 宽度在 `232px` 与 `64px` 间切换。
  - `el-menu` 使用 Element Plus 的 `collapse` 属性。
  - 品牌区收起后只显示图标，菜单文字由 `el-menu` 折叠处理。
  - 在 header 左侧或 aside 顶部增加一个图标按钮用于展开/收起。
  - 可选：使用 `localStorage` 记住老师上一次选择。
- 影响范围：
  - `frontend/apps/admin/src/layouts/AdminLayout.vue`
  - `frontend/apps/admin/src/styles/index.scss`
- 验证方案：
  - 浏览器打开管理端，点击收起按钮后 aside 变为图标栏，当前路由高亮仍正确。
  - 进入 `/exam/question/correction` 后，题目上下文和右侧审核栏可见宽度增加。
  - 刷新页面后，如果做了持久化，收起状态保持。

### 2. 管理端审核队列压缩为窄队列

- 当前现状：
  - 审核队列宽度 `280-330px`。
  - 队列卡片包含长题干、学生、AI 状态、提交时间，信息密度偏低。
- 判断：
  - 队列的任务是快速切换记录，不应占用接近一个详情面板的宽度。
- 修改方案：
  - 队列宽度调整为 `220-260px`，使用固定上限。
  - 队列项改成三行以内：
    - 第 1 行：题干两行截断。
    - 第 2 行：学生名 + 审核状态。
    - 第 3 行：AI 标签 + 时间短格式。
  - 分页保留在底部，筛选条件保留在页面顶部。
  - 在窄屏或小于 `1180px` 时仍回退单列。
- 影响范围：
  - `QuestionCorrectionReviewView.vue` 样式。
- 验证方案：
  - 1440px 宽度下，队列宽度不超过 `260px`。
  - 长题干不会撑开布局。
  - 当前选中记录、AI 状态和学生信息仍可快速识别。

### 3. 管理端审核处理与 AI 建议整合

- 当前现状：
  - 右侧栏里“审核处理”在上，“AI 预审建议”在下。
  - AI 意见内容长时，老师需要滚动很多才能查看和修改审核意见。
  - AI 建议不会自动填到审核结果和审核意见中。
- 判断：
  - 审核操作应是右侧首屏核心。AI 是辅助输入，应直接减少老师填写动作，而不是单独作为只读长文本。
- 修改方案：
  - 右侧固定操作栏宽度建议 `420-480px`。
  - 顶部做“审核处理”主卡片：
    - 审核结果使用明显的 segmented/radio button：通过、驳回、不采纳 AI。
    - 审核意见 textarea 置顶，建议 `6-8` 行。
    - 按钮固定在卡片底部：仅保存、保存并下一题。
  - AI 预审成功后：
    - 如果当前记录仍是待审核，且老师尚未手动编辑审核结果/审核意见，则自动填入：
      - `reviewForm.reviewResult = ai.reviewResult === APPROVED ? APPROVED : REJECTED`；`UNCERTAIN` 不自动改结果。
      - `reviewForm.reviewComment = ai.studentFeedback || ai.reviewComment`。
    - 如果老师已经编辑过，显示“应用 AI 建议”按钮，由老师手动覆盖。
  - AI 建议卡片改为结构化摘要，不再只是长段落：
    - 建议：通过 / 驳回 / 不确定。
    - 给老师看的判断理由。
    - 可返回给学生的修改建议。
    - 置信度。
    - 原始/补充信息收进折叠区。
- 影响范围：
  - `QuestionCorrectionReviewView.vue`
  - `frontend/packages/api-client/src/adminOperations.ts`
  - 后端 AI prompt、解析和记录字段，见需求 4。
- 验证方案：
  - AI 预审成功且老师未编辑时，审核结果和审核意见自动带入。
  - 老师手动修改后再次刷新详情，不被 AI 覆盖。
  - AI 为 `UNCERTAIN` 时不自动通过或驳回，只提示老师判断。
  - “保存并下一题”后自动进入下一条待审核记录。

### 4. AI 预审返回结构升级

- 当前现状：
  - `QuestionCorrectionAiReviewService` 要求模型输出：
    - `reviewResult`
    - `reviewComment`
    - `confidence`
    - `reason`
  - 数据表 `t_question_correction_ai_review_record` 当前存储 `review_comment`、`reason`、`confidence`、`raw_content` 等。
- 判断：
  - “给老师看的理由”和“返回给学生的理由”语义不同，不能只靠一个 `reviewComment` 兼用。
- 修改方案：
  - 后端 prompt 改为要求 JSON：
    - `reviewResult`: `APPROVED|REJECTED|UNCERTAIN`
    - `teacherReason`: 给老师看的判断依据。
    - `studentFeedback`: 可直接放入审核意见给学生看的反馈。
    - `missingPoints`: 学生改错还缺哪些关键点，数组。
    - `confidence`: `0-1`
  - 新增 Flyway 迁移：
    - `teacher_reason text`
    - `student_feedback text`
    - `missing_points jsonb`
  - 兼容旧记录：
    - 旧 `reason` 映射为 `teacherReason`。
    - 旧 `review_comment` 映射为 `studentFeedback` 或 `reviewComment`。
  - 前端类型同步扩展。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/service/QuestionCorrectionAiReviewService.java`
  - `source/xzs/src/main/resources/db/migration`
  - `frontend/packages/api-client/src/adminOperations.ts`
  - `QuestionCorrectionReviewView.vue`
- 验证方案：
  - 旧 AI 记录仍可显示。
  - 新 AI 记录能显示老师理由、学生反馈、缺失点和置信度。
  - AI 响应缺字段时前端有兜底，不空白、不报错。

### 5. 学生错题本改为更紧凑的队列工作台

- 当前现状：
  - `QuestionErrorView.vue` 队列宽度 `280-320px`。
  - 右侧“老师驳回意见”和“重新提交改错”纵向堆叠，长内容时学生需要滚动。
- 判断：
  - 学生端核心任务是边看题目、解析、老师意见，边写两段改错。提交区应该在首屏稳定可见。
- 修改方案：
  - 页面主宽度从 `1180px` 放宽到 `min(1440px, calc(100vw - 32px))`，只针对错题本页面或学生 Shell 增加页面级宽屏模式。
  - 队列宽度压缩到 `220-260px`。
  - 右侧改错栏宽度建议 `380-440px`。
  - 老师驳回意见放在右侧最顶部的红色提示卡中，始终在提交表单上方。
  - 表单 textarea 调整为 `6` 行左右，按钮紧跟表单，不被历史区挤到下方。
  - 历史区改为折叠/次级信息，默认不抢首屏。
- 影响范围：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - 可选：`frontend/apps/student/src/layouts/ShellLayout.vue`
- 验证方案：
  - 1440px 宽度下，学生能同时看到队列、题目上下文和提交表单。
  - 被驳回记录首屏能看到老师意见和两个输入框。
  - 未提交、待审核、已通过、被驳回四种状态显示正确。

## 执行顺序

1. 管理端外层菜单收起能力。
2. 管理端审核页布局重排：窄队列、宽题目区、右侧操作栏置顶。
3. AI 预审自动填表逻辑，先使用现有字段 `reviewResult/reviewComment/reason/confidence`。
4. AI 返回结构升级和数据库迁移。
5. 学生端错题本布局重排：窄队列、题目区、右侧提交栏。
6. 浏览器级视觉和交互验收。

## 风险与待确认

- AI 自动填审核意见必须只作为草稿，不能自动保存、不能自动通过或驳回。
- 如果要把“返回给学生的理由”单独保存，需要数据库迁移；如果先不迁移，可以短期把 `reviewComment` 当作学生反馈，`reason` 当作老师理由，但语义不够稳定。
- 管理端菜单收起会影响所有后台页面，需要检查 dashboard、用户、题目、班级等页面在收起状态下没有布局问题。
- 学生端 Shell 当前内容宽度限制为 `1180px`，如果只为错题本放宽，需要加页面级 class 或 CSS 变量，避免影响所有学生页面。

## 视觉参考

视觉稿位于 `.tmp/question-correction-layout-mockup.html`，截图输出为 `.tmp/question-correction-layout-mockup.png`。
