# 管理员兼任负责老师、AI 预审配置与改错体验优化方案

## 背景与现状

- 已确认本地 `t_user` 当前只有学生和管理员账号，没有 `role = 2` 的老师账号。
- 管理端路由和左侧菜单已经包含老师列表：`/user/teacher/list`，对应 `frontend/apps/admin/src/views/user/UserListView.vue`，后端 `/api/admin/user/page/list` 也支持按 `role = 2` 查询和新增老师。
- 管理员访问老师列表接口返回成功但数据为空，因此“本地没有老师”是数据问题，不是接口缺失。
- 班级编辑页的负责老师下拉当前只请求 `role = 2` 用户；后端班级保存也校验负责老师必须是 `RoleEnum.TEACHER`。
- AI 预审配置入口当前只在个人简介页显示给 `role === 2`，后端 `/api/admin/questionCorrection/ai/config/select|edit` 也只允许 `classScopeService.isTeacher(currentUser)`。
- 当前 `RoleEnum` 是单角色模型：`1` 学生、`2` 老师、`3` 管理员。直接把管理员改成老师会丢失管理员权限，不适合满足“管理员也可以同时是老师”。

## 结论

推荐保留现有单角色枚举，把“能否作为负责老师”从“用户角色必须等于老师”改成“老师角色或管理员角色都可被班级指定为负责老师”。AI 预审配置仍按 `teacher_user_id` 存储，但允许被班级指定为负责老师的管理员维护自己的配置。

补充结论：学生端重新提交改错不应再使用弹窗。推荐在错题详情页直接内嵌改错编辑区，让学生一边看题面、选项、解析、自己的答案和正确答案，一边修改“我错在哪里”和“正确思路”。老师驳回意见需要从历史时间线中提升到改错编辑区顶部，以醒目的驳回提示展示。

二次体验优化结论：老师端改错审核应从“列表 + 弹窗长内容”改为“列表 + 双栏审核工作台”。左侧稳定展示题目、解析、学生答案和正确答案，右侧展示学生改错、AI 预审、审核结果和审核意见，并支持保存后自动切到下一条待审核记录。学生端错题本也应压缩左侧列表宽度，把主要空间让给题目上下文和改错表单。AI 预审应新增手动触发能力，支持单条重跑和按当前筛选条件批量触发，便于用本地已配置的管理员 API Key 验证调用链。

## 需求拆解

### 1. 管理员可以新增老师

- 当前现状：老师列表和老师编辑路由已存在，后端也支持 `role = 2` 的用户新增；本地只是没有老师数据。
- 判断：功能主体存在，但入口对用户不够明显；如果管理员只看顶部导航，容易误以为没有老师管理页。
- 修改方案：
  - 保留 `/user/teacher/list` 和 `/user/teacher/edit`。
  - 在用户中心页面或顶部导航中强化老师管理入口，例如管理员顶部增加“老师管理”快捷入口，或在“用户中心”入口文案/默认落点中明确包含学生、老师、管理员。
  - 老师列表空态增加“暂无老师，可点击添加创建老师账号”的说明。
- 影响范围：
  - `frontend/apps/admin/src/layouts/AdminLayout.vue`
  - `frontend/apps/admin/src/views/user/UserListView.vue`
- 验证方案：
  - 管理员登录后能从可见入口进入老师列表。
  - 老师列表为空时显示明确空态。
  - 点击添加创建 `role = 2` 老师后，老师列表出现该账号。

### 2. 管理员也可以作为班级负责老师

- 当前现状：班级编辑页下拉只加载 `role = 2`；后端 `ClassController.edit` 也拒绝非老师角色作为负责老师。
- 判断：这是“管理员同时是老师”的核心阻塞。
- 修改方案：
  - 在 `ClassScopeService` 中新增独立能力判断，例如 `canBeClassTeacher(User user)`，允许 `RoleEnum.TEACHER` 和 `RoleEnum.ADMIN`。
  - 不改现有 `isTeacher(User user)` 的含义，避免管理员被错误套用老师的班级范围限制。
  - 班级保存时使用 `canBeClassTeacher` 校验负责老师。
  - 负责老师候选用户接口支持返回 `role in (2, 3)`，前端班级编辑页下拉展示“老师/管理员”身份标记。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/service/ClassScopeService.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/service/impl/ClassScopeServiceImpl.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/admin/ClassController.java`
  - `source/xzs/src/main/resources/mapper/UserMapper.xml`
  - `frontend/apps/admin/src/views/class/ClassEditView.vue`
  - `frontend/packages/api-client/src/adminUser.ts`
- 验证方案：
  - 管理员账号出现在班级负责老师候选下拉中。
  - 新建班级时可以选择管理员作为负责老师。
  - 老师角色仍只能管理自己负责的班级；管理员仍保留全局管理权限。

### 3. 管理员兼任负责老师后可以配置 AI 预审

- 当前现状：AI 配置页面和接口只允许 `role = 2`；管理员访问接口会返回“AI 预审配置仅班级负责老师可维护”。
- 判断：如果管理员被班级指定为负责老师，自动 AI 预审已经可以通过 `t_class.teacher_id` 找到管理员用户，但管理员无法维护自己的配置。
- 修改方案：
  - 新增能力判断，例如 `canConfigureAiReview(User user)`：允许纯老师，允许管理员；如果希望更严格，可要求管理员至少负责一个启用班级。
  - 后端 AI 配置 select/edit 从 `isTeacher` 改为 `canConfigureAiReview`。
  - 前端个人简介页 `canConfigureAiReview` 从 `role === 2` 改为 `role === 2 || role === 3`。
  - 页面文案改为“配置当前账号作为班级负责老师时使用的 AI 预审接口”。
  - 保持 AI 只做预审建议，不自动通过或驳回。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/admin/QuestionCorrectionController.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/service/ClassScopeService.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/service/impl/ClassScopeServiceImpl.java`
  - `frontend/apps/admin/src/views/profile/ProfileView.vue`
- 验证方案：
  - 管理员登录个人简介页能看到 AI 审核配置。
  - 管理员能保存 OpenAI-compatible 配置。
  - 负责老师为该管理员的班级学生提交改错后，自动写入 AI 预审记录。
  - AI 预审结果只展示在老师/管理员审核页，不改变 `review_status`。

### 4. 管理员与老师视角权限保持清晰

- 当前现状：`isTeacher` 被多个列表和编辑接口用于班级范围限制；如果把管理员直接视为老师，会让管理员意外只能看自己负责班级。
- 判断：必须区分“平台权限”和“负责老师能力”。
- 修改方案：
  - `isTeacher` 保持纯 `role = 2`，只用于老师范围限制。
  - 新增 `canBeClassTeacher` 或 `canConfigureAiReview`，只用于负责老师候选和 AI 配置。
  - AI 自动触发继续以 `t_class.teacher_id` 为准，不根据提交人或当前登录人判断。
- 影响范围：
  - 班级管理、学生管理、任务、答卷、改错审核中的范围过滤逻辑。
- 验证方案：
  - 管理员作为负责老师后仍能看到全部管理员菜单和全量数据。
  - 老师角色仍只看到自己班级数据。
  - 未指定为班级负责老师的管理员配置 AI 后，不会影响其他班级，除非某班级 `teacher_id` 指向该管理员。

### 5. 学生端改错提交改为内嵌编辑

- 当前现状：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue` 当前在右侧错题详情中展示题目和已有改错内容，但点击“提交改错/重新提交改错”后会打开 `el-dialog`。
  - 弹窗里只有两个文本框，遮住了题面、选项、解析、学生答案和正确答案，学生需要来回记忆上下文。
  - 题目上下文数据已经存在：`getQuestionAnswerDetail` 返回 `questionVM` 和 `questionAnswerVM`；`QuestionReview.vue` 已经复用 `@xzs/question-renderer` 的 `QuestionCorrectionContext`，可以展示题面、选项、解析、学生答案、正确答案和结果。
- 判断：
  - 这是前端交互问题，不需要新增后端字段或接口。
  - 应保留现有错题列表 + 详情双栏结构，把“改错”区从只读内容改成状态驱动的内嵌编辑区。
- 修改方案：
  - 删除 `QuestionErrorView.vue` 中的改错弹窗状态和模板，包括 `correctionDialogVisible`、`correctionDialogTitle`、`openCorrectionDialog` 以及 `<el-dialog>`。
  - 在右侧详情的“改错” section 内直接放表单：
    - `UNSUBMITTED`：显示空表单，主按钮为“提交改错”。
    - `REJECTED`：表单默认填入上次提交内容，主按钮为“重新提交改错”。
    - `SUBMITTED`：展示只读提交内容和“等待老师审核”的状态，不允许编辑。
    - `APPROVED`：展示只读提交内容和“老师已通过”的状态，不允许编辑。
  - “题目” section 继续使用 `QuestionReview`/`QuestionCorrectionContext`，保证学生编辑时同屏可见题面、选项、解析、学生答案和正确答案。
  - 提交逻辑沿用 `submitQuestionCorrection`，提交成功后刷新当前错题详情和状态层，不改 API。
  - 右侧详情在窄屏下保持单列堆叠；表单按钮固定在改错区底部，不使用遮罩弹窗。
- 影响范围：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - 可选：如果表单区逻辑膨胀，再拆为本地组件 `frontend/apps/student/src/components/QuestionCorrectionEditor.vue`，但第一版推荐先保持在页面内，减少跨文件改动。
- 验证方案：
  - 未提交错题：选择错题后直接看到题目上下文和改错表单；填写两项后可提交成功。
  - 被驳回错题：选择错题后直接看到老师驳回意见、题目上下文和带上次内容的表单；修改后可重新提交。
  - 待审核/已通过错题：只能查看已提交内容，不能编辑或重复提交。
  - 桌面宽度下题目上下文和改错编辑区同屏可见；移动宽度下内容按题目、审核意见、改错表单顺序自然堆叠。

### 6. 老师审核意见在学生端更显眼

- 当前现状：
  - 学生端 `QuestionErrorView.vue` 只在“历史”时间线中以普通文本显示 `审核意见：{{ correction.review_comment }}`。
  - 从截图看，驳回意见位于页面下方，视觉权重低；学生重新提交时弹窗遮住背景，无法稳定对照老师意见。
- 判断：
  - 老师审核意见是学生重新提交的核心输入，应出现在改错表单上方，而不是只作为历史记录。
  - 只需要调整前端展示；后端 `QuestionCorrectionRecord.review_comment` 已经返回。
- 修改方案：
  - 在“改错” section 顶部增加醒目的意见提示：
    - 当 `selectedCorrectionLayer === 'REJECTED' && correction.review_comment` 时，显示 `el-alert` 或同等样式块。
    - 标题使用“老师驳回意见”，正文显示完整 `review_comment`，不使用 tooltip 截断。
    - 样式使用 danger/红色左边框/浅红背景，让它高于历史时间线。
  - 历史 section 仍保留审核记录摘要，但不再承担主要提示职责。
  - 如果后续学生端需要展示多轮历史，当前接口只返回最新 correction 主记录；多轮完整历史应另开接口，不纳入本次 UI 优化。
- 影响范围：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
- 验证方案：
  - 老师驳回并填写意见后，学生进入“改错被驳回”层，右侧改错区顶部首先看到“老师驳回意见”。
  - 驳回意见较长时完整换行展示，不被表格 tooltip 或弹窗遮罩截断。
  - 无审核意见或非驳回状态时，不显示空提示块。

### 7. 老师端改错审核与学生端上下文保持一致

- 当前现状：
  - 老师端 `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue` 在审核弹窗中使用 `QuestionCorrectionContext`，已经能看到题目上下文和解析。
  - 学生端也间接使用同一个渲染组件，但提交表单被弹窗割裂。
- 判断：
  - 两端不需要共用整个页面布局，但应共用题目上下文渲染能力，避免“老师看得到的信息”和“学生改错时看得到的信息”不一致。
- 修改方案：
  - 保持 `@xzs/question-renderer/src/QuestionCorrectionContext.vue` 作为共享上下文组件。
  - 学生端继续通过 `QuestionReview.vue` 使用该组件；如果需要更贴近老师端，可直接在 `QuestionErrorView.vue` 引入 `QuestionCorrectionContext` 并传 `show-result="true"`。
  - 老师端审核弹窗当前可暂不改为非弹窗；本次用户痛点是学生重新提交弹窗遮挡上下文。
  - 可选优化：老师端弹窗宽度从 `860px` 调整为更宽或全屏抽屉，但不作为本次必要项，避免扩大范围。
- 影响范围：
  - `frontend/packages/question-renderer/src/QuestionCorrectionContext.vue`
  - `frontend/apps/student/src/components/QuestionReview.vue`
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
- 验证方案：
  - 同一道题在老师改错审核和学生错题本中展示的题面、选项、解析、学生答案、正确答案一致。
  - 选择题能标出学生选择和正确答案；填空/简答题能展示学生答案和正确答案/参考答案。

### 8. 老师端改错审核改为双栏连续审批工作台

- 当前现状：
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue` 当前先展示表格列表，再通过 `el-dialog width="860px"` 打开审核详情。
  - 弹窗内部按纵向顺序展示题目上下文、AI 预审、学生提交、审核表单和审核历史；题目较长时老师需要大量滚动，审核表单也容易被挤到页面底部。
  - 列表页已经有 `getAdminQuestionCorrectionPage` 和 `getAdminQuestionCorrection`，单条详情已经包含题干、选项、解析、学生答案、正确答案、AI 预审和历史记录，数据足够支撑双栏工作台。
- 判断：
  - 这是前端信息架构问题，不需要改变改错审核主数据结构。
  - 审核动作应围绕“一条待审核记录”展开，表格列表应退为队列/导航，不应遮挡审核上下文。
- 修改方案：
  - 将页面改成三段式工作台：
    - 顶部：状态、班级、AI 状态等筛选项，以及“查询”“AI 批量预审”按钮。
    - 左侧窄队列：显示待审核记录列表，包含学生、题干摘要、提交时间、AI 状态；宽度控制在 300-360px，可滚动。
    - 主区域双栏：左栏为题目上下文，右栏为学生改错与审核操作。
  - 主区域左栏：
    - 复用 `QuestionCorrectionContext`，展示题面、选项、学生选择、正确答案、解析。
    - 左栏独立滚动，保证题目很长时不把右侧审核操作推走。
  - 主区域右栏：
    - 顶部显示当前学生、提交时间、审核状态、AI 预审状态。
    - AI 预审区域显示建议结果、建议意见、理由、置信度、失败原因，并提供“重新 AI 预审当前题”按钮。
    - 学生改错区域展示“我错在哪里”“正确思路是什么”，内容完整换行展示。
    - 审核区域固定放在右栏靠上位置，包含通过/不通过、审核意见、保存按钮。
    - 审核历史折叠在底部或用轻量表格展示，避免抢占主要审核空间。
  - 连续审批：
    - 保存审核成功后，默认自动选择当前筛选队列里的下一条 `SUBMITTED` 记录。
    - 如果当前页没有下一条，自动刷新列表并选中刷新后的第一条待审核记录。
    - 提供“保存并下一题”和“仅保存”两个按钮；推荐默认主按钮为“保存并下一题”，减少老师操作。
    - 保留键盘友好路径：后续可扩展快捷键，但本次不强制实现，避免增加误触风险。
- 影响范围：
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
  - `frontend/packages/api-client/src/adminOperations.ts`
  - 可选：如组件过长，可拆出 `frontend/apps/admin/src/views/question/components/CorrectionReviewWorkspace.vue`、`CorrectionReviewQueue.vue`、`CorrectionReviewDecisionPanel.vue`。
- 验证方案：
  - 管理员进入改错审核页后，无需弹窗即可看到第一条待审核记录详情。
  - 题目很长时，左栏滚动不影响右栏审核表单位置。
  - 点击队列中任一记录，左栏题目和右栏改错内容同步切换。
  - 保存“通过/不通过”后，列表状态刷新，并自动跳到下一条待审核记录。
  - 不通过且审核意见为空时仍被阻止。

### 9. 学生端错题本改为紧凑列表 + 双栏详情

- 当前现状：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue` 当前整体是左侧错题表格、右侧详情。
  - 左侧表格包含题干、题型、学科、状态、做题时间等列，占据了接近半屏；右侧题目和改错内容较长时需要大量纵向滚动。
  - 右侧已经内嵌改错表单，但题目上下文、改错表单、历史仍按纵向堆叠，截图中题目区域很容易把改错区域推到屏幕下方。
- 判断：
  - 学生端核心任务是“选一题并改正”，列表只需要帮助定位错题，不应占据主要阅读空间。
  - 详情区也应拆成题目上下文和改错操作两栏，减少上下滚动。
- 修改方案：
  - 左侧列表改为紧凑错题队列：
    - 宽度控制在 280-340px。
    - 用简短题干摘要 + 状态 tag + 学科/时间元信息替代表格多列。
    - 顶部保留状态 tabs 和刷新按钮；分页放在队列底部。
    - 当前选中题高亮，避免用宽表格占空间。
  - 右侧详情改为双栏：
    - 左栏：题目、选项、学生答案、正确答案、解析，继续复用 `QuestionReview`/`QuestionCorrectionContext`。
    - 右栏：老师驳回意见、改错表单/只读改错内容、历史。
  - 响应式：
    - 桌面端使用 `grid-template-columns: 320px minmax(0, 1fr)`，详情内部再分 `minmax(0, 1.2fr) minmax(360px, 0.8fr)`。
    - 窄屏下降级为单列，顺序为列表、题目、改错。
  - 保留现有提交接口和状态逻辑，不新增后端接口。
- 影响范围：
  - `frontend/apps/student/src/views/question/QuestionErrorView.vue`
  - 可选：拆出 `QuestionErrorQueue.vue` 和 `QuestionCorrectionPanel.vue` 以控制页面复杂度。
- 验证方案：
  - 错题本左侧列表不再横向挤占大面积，题干长文本不会导致整体表格过宽。
  - 被驳回错题打开后，题目上下文和改错表单在桌面端能同屏并排看到。
  - 未提交、待审核、已通过、被驳回四种状态显示和提交权限保持正确。
  - 移动端或窄屏下内容不重叠、不溢出。

### 10. AI 预审支持手动单题触发和批量触发

- 当前现状：
  - 学生提交或重新提交改错后，学生端 `QuestionCorrectionController` 会调用 `questionCorrectionAiReviewService.triggerAfterCommit(correctionId, "AUTO_SUBMIT|AUTO_RESUBMIT")` 自动预审。
  - 管理端目前只有 AI 配置查询/保存接口：`/api/admin/questionCorrection/ai/config/select|edit`。
  - `QuestionCorrectionAiReviewService.preReview(correctionId, triggerType)` 已经是 public 方法，能执行 OpenAI-compatible 调用并写入 `t_question_correction_ai_review_record`。
  - 管理端列表和详情已经能展示最新 AI 预审记录。
- 判断：
  - 手动触发不需要重写 AI 调用链，应复用 `preReview`，只补管理端接口、权限校验、批量筛选和 UI 入口。
  - AI 仍然只产生预审建议，不能自动通过或驳回。
- 修改方案：
  - 后端新增接口：
    - `POST /api/admin/questionCorrection/ai/review/{id}`：手动触发单条改错 AI 预审。
    - `POST /api/admin/questionCorrection/ai/review/batch`：按当前筛选条件批量触发 AI 预审。
  - 单题触发：
    - 复用现有 `select`/`correctionScopeSql` 权限逻辑，老师只能触发自己班级内记录，管理员可触发全量。
    - 推荐异步执行：接口先插入或触发后台任务并立即返回“已开始预审”，前端轮询刷新详情。
    - `triggerType` 使用 `MANUAL_SINGLE`。
  - 批量触发：
    - 请求体复用 `QuestionCorrectionPageRequest` 的筛选字段，默认只触发 `reviewStatus = SUBMITTED` 的记录。
    - 支持“按当前筛选条件全量”，但应设置单次上限，例如 50 或 100 条，避免一次误触发大量外部 API 调用。
    - 查询出符合当前权限和筛选条件的 correction ids 后逐条异步调用 `preReview(id, "MANUAL_BATCH")`。
    - 返回 `acceptedCount`、`skippedCount` 和提示文案。
  - UI 入口：
    - 改错审核顶部增加“AI 批量预审”按钮，旁边提示“按当前筛选条件触发，默认仅待审核记录”。
    - 队列行或右栏 AI 区域增加“AI 预审当前题/重新预审”按钮。
    - 触发后按钮进入 loading 状态，成功后刷新当前详情和列表 AI 状态。
  - 本地测试：
    - 用户已说明本地开发环境配置了管理员 API Key。测试时需确认被测改错记录所属班级的负责老师是该管理员；否则现有 AI 设计会按班级负责老师配置执行，并可能返回“负责老师未配置 AI 预审”。
    - 如果希望“管理员无论是否为负责老师都用当前管理员 API Key 强制测试”，那是另一种语义，会偏离“自动触发用负责老师配置”的既定规则；本方案不推荐默认这么做。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/controller/admin/QuestionCorrectionController.java`
  - `source/xzs/src/main/java/com/mindskip/xzs/service/QuestionCorrectionAiReviewService.java`
  - `frontend/packages/api-client/src/adminOperations.ts`
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
  - 后端测试：`source/xzs/src/test/java/com/mindskip/xzs/controller/admin/QuestionCorrectionControllerTest.java`
- 验证方案：
  - 管理员对单条待审核改错点击“AI 预审当前题”，后端新增一条 `MANUAL_SINGLE` AI 记录，页面刷新后展示最新建议。
  - 管理员点击“AI 批量预审”，符合当前筛选条件的多条待审核改错产生 `MANUAL_BATCH` AI 记录。
  - 老师账号只能触发自己负责班级的记录，不能触发其他班级记录。
  - AI 返回 `APPROVED/REJECTED/UNCERTAIN` 时只预填或展示建议，不改变 `review_status`。
  - API Key 配置错误或调用失败时，页面显示失败原因，不影响老师人工审核。

## 执行顺序

1. 已完成的权限基础：后端增加“可作为负责老师/可配置 AI”的能力方法，班级负责人允许老师或管理员，管理员可配置 AI。
2. 已完成的学生端第一步：学生端改错提交去掉弹窗，改成内嵌表单，并把驳回意见提升到表单上方。
3. 先补后端 AI 手动触发接口：单题触发、按筛选条件批量触发、权限校验、批量上限和测试覆盖。
4. 重构老师端改错审核页为工作台：队列 + 左题目上下文 + 右审核面板 + 连续审批。
5. 重构学生端错题本布局：紧凑错题队列 + 题目上下文/改错面板双栏。
6. 前端接入 AI 手动触发按钮和状态刷新。
7. 用本地 Neon test branch 和已配置的管理员 API Key 做真实单题 AI 调用测试；再做批量小样本测试。
8. 完整验证：后端测试、前端构建、浏览器桌面/窄屏截图验收、AI 成功/失败路径验收。

## 风险与待确认

- 待确认：是否允许“所有管理员”配置 AI，还是只有“已被某个班级指定为负责老师的管理员”能配置。推荐先允许所有管理员配置，实际触发仍只发生在 `t_class.teacher_id` 指向该管理员时。
- 风险：如果把 `isTeacher` 语义改成包含管理员，会影响很多班级范围过滤逻辑；方案明确不这么做。
- 风险：负责老师候选如果混入禁用用户，可能导致自动预审找不到可用人。候选查询应只返回 `deleted = false` 且 `status = 1` 的用户。
- 风险：学生端如果后续要展示多轮驳回历史，当前 `getQuestionCorrection` 只返回最新主记录，不足以完整呈现多轮审核链路。本次只强化最新驳回意见。
- 风险：`QuestionCorrectionContext` 已经显示“解析”，但如果题库数据本身 `analyze` 为空，只能展示“暂无解析”；这不是 UI 问题，需要从题库数据补解析。
- 待确认：AI 批量预审的“全量”是否限定为当前筛选条件下的待审核记录。推荐限定为当前筛选条件，并默认 `SUBMITTED`，避免对历史已通过/已驳回记录反复消耗 API。
- 待确认：批量触发单次上限。推荐第一版设置为 50 条，后续根据调用耗时和费用再调。
- 风险：当前 AI 调用按改错所属班级负责老师配置执行。若本地管理员已配置 API Key，但被测班级负责老师不是该管理员，手动预审仍会跳过或使用其他负责老师配置。测试前应把该管理员设为被测班级负责老师，或明确要增加“用当前账号配置强制测试”的特殊入口。
- 风险：连续审批如果保存后自动跳转太快，老师可能来不及确认结果。建议保存成功后 toast 提示，并在右栏顶部保留上一条保存结果的短提示。
