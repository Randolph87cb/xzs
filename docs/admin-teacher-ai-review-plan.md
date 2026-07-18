# 管理员兼任负责老师与 AI 预审配置方案

## 背景与现状

- 已确认本地 `t_user` 当前只有学生和管理员账号，没有 `role = 2` 的老师账号。
- 管理端路由和左侧菜单已经包含老师列表：`/user/teacher/list`，对应 `frontend/apps/admin/src/views/user/UserListView.vue`，后端 `/api/admin/user/page/list` 也支持按 `role = 2` 查询和新增老师。
- 管理员访问老师列表接口返回成功但数据为空，因此“本地没有老师”是数据问题，不是接口缺失。
- 班级编辑页的负责老师下拉当前只请求 `role = 2` 用户；后端班级保存也校验负责老师必须是 `RoleEnum.TEACHER`。
- AI 预审配置入口当前只在个人简介页显示给 `role === 2`，后端 `/api/admin/questionCorrection/ai/config/select|edit` 也只允许 `classScopeService.isTeacher(currentUser)`。
- 当前 `RoleEnum` 是单角色模型：`1` 学生、`2` 老师、`3` 管理员。直接把管理员改成老师会丢失管理员权限，不适合满足“管理员也可以同时是老师”。

## 结论

推荐保留现有单角色枚举，把“能否作为负责老师”从“用户角色必须等于老师”改成“老师角色或管理员角色都可被班级指定为负责老师”。AI 预审配置仍按 `teacher_user_id` 存储，但允许被班级指定为负责老师的管理员维护自己的配置。

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

## 执行顺序

1. 后端先增加“可作为负责老师/可配置 AI”的能力方法，避免改动 `isTeacher` 带来权限回归。
2. 放开班级负责老师校验，允许老师或管理员。
3. 增加或扩展负责老师候选查询，返回 `role in (2, 3)`。
4. 前端班级编辑页使用新的候选数据，展示老师和管理员。
5. 前端个人简介页对管理员也显示 AI 配置；后端 AI 配置接口同步放开。
6. 补测试：班级负责人校验、管理员 AI 配置、老师范围限制不回归、AI 自动预审仍按 `t_class.teacher_id`。

## 风险与待确认

- 待确认：是否允许“所有管理员”配置 AI，还是只有“已被某个班级指定为负责老师的管理员”能配置。推荐先允许所有管理员配置，实际触发仍只发生在 `t_class.teacher_id` 指向该管理员时。
- 风险：如果把 `isTeacher` 语义改成包含管理员，会影响很多班级范围过滤逻辑；方案明确不这么做。
- 风险：负责老师候选如果混入禁用用户，可能导致自动预审找不到可用人。候选查询应只返回 `deleted = false` 且 `status = 1` 的用户。
