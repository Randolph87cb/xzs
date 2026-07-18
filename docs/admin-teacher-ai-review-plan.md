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

## 执行顺序

1. 后端先增加“可作为负责老师/可配置 AI”的能力方法，避免改动 `isTeacher` 带来权限回归。
2. 放开班级负责老师校验，允许老师或管理员。
3. 增加或扩展负责老师候选查询，返回 `role in (2, 3)`。
4. 前端班级编辑页使用新的候选数据，展示老师和管理员。
5. 前端个人简介页对管理员也显示 AI 配置；后端 AI 配置接口同步放开。
6. 学生端改错详情页去掉提交弹窗，改成内嵌表单，并把驳回意见提升到表单上方。
7. 补测试：班级负责人校验、管理员 AI 配置、老师范围限制不回归、AI 自动预审仍按 `t_class.teacher_id`。
8. 前端浏览器验收：老师审核页和学生错题本都能看到题面、选项、解析、学生答案、正确答案；学生重新提交不再出现遮罩弹窗。

## 风险与待确认

- 待确认：是否允许“所有管理员”配置 AI，还是只有“已被某个班级指定为负责老师的管理员”能配置。推荐先允许所有管理员配置，实际触发仍只发生在 `t_class.teacher_id` 指向该管理员时。
- 风险：如果把 `isTeacher` 语义改成包含管理员，会影响很多班级范围过滤逻辑；方案明确不这么做。
- 风险：负责老师候选如果混入禁用用户，可能导致自动预审找不到可用人。候选查询应只返回 `deleted = false` 且 `status = 1` 的用户。
- 风险：学生端如果后续要展示多轮驳回历史，当前 `getQuestionCorrection` 只返回最新主记录，不足以完整呈现多轮审核链路。本次只强化最新驳回意见。
- 风险：`QuestionCorrectionContext` 已经显示“解析”，但如果题库数据本身 `analyze` 为空，只能展示“暂无解析”；这不是 UI 问题，需要从题库数据补解析。
