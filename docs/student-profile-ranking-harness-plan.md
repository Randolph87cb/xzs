# 学生端个人信息、消息移除与班级排行榜 Harness 方案

## 目标

用 harness + subagent 的方式完成 5 个需求：

1. 管理端修改用户时，密码为空则不修改原密码。
2. 学生端主页右上角显示当前用户名字。
3. 学生个人资料只保留修改昵称，真实姓名只能由管理员或老师修改。
4. 学生端移除消息版块。
5. 增加班级排行榜，展示同班同学做题情况、正确率、错题改错次数等，并通过页面设计强化比较和追赶动机。

完成标准不是“能编译”，而是每个功能都能通过接口、页面和数据行为验证正常运行。

## 适用范围

适用：

- Spring Boot 后端 `source/xzs`。
- Vue 3 + Vite 学生端 `frontend/apps/student`。
- Vue 3 + Vite 管理端 `frontend/apps/admin`。
- 共享 API client `frontend/packages/api-client`。
- PostgreSQL Flyway 迁移和初始化脚本。

不适用：

- 微信小程序端，除非后续明确要求同步。
- 管理端消息中心的彻底删除。当前只移除学生端消息入口，后端消息接口和管理端消息功能先保留，降低影响面。
- 大规模重构认证、用户体系或答题统计表。

## 输入

执行前需要确认或读取：

- 根目录 `AGENTS.md`。
- 当前需求清单。
- 现有用户编辑接口：`/api/admin/user/edit`。
- 现有学生用户接口：`/api/student/user/current`、`/api/student/user/update`。
- 现有答卷数据表：`t_exam_paper_answer`。
- 现有错题改错表：`t_question_correction_record`。
- 现有学生端布局、路由、个人中心和 dashboard 页面。

## 角色分工

主线程：

- 维护本 harness 文档。
- 创建 subagent，不直接做功能代码改动。
- 审查 subagent 结果，运行功能验证，必要时要求 subagent 修复。
- 最终整理变更、提交和 push。

Backend subagent：

- 负责后端、数据库迁移、Mapper、后端测试。
- 不修改前端文件。
- 不提交 Git。

Frontend subagent：

- 负责学生端、管理端和共享 API client 的页面与类型改动。
- 不修改后端 Java、SQL、Flyway 文件。
- 不提交 Git。

## Git 策略

- subagent 不创建提交、不 push。
- 主线程在所有功能验证通过后统一 `git add`、`git commit`、`git push`。
- 提交信息使用中文。

## 执行流程

### 阶段 1：文档与接口契约

主线程完成：

- 写清本 harness 文档。
- 固定后端和前端之间的接口契约：
  - 用户响应新增 `nickName`。
  - 学生更新接口只接收 `nickName`。
  - 新增班级排行榜接口 `POST /api/student/dashboard/class/ranking`。

检查点：

- 文档包含目标、范围、输入、流程、角色、检查点、产出、失败处理和 Git 策略。
- subagent 修改范围不重叠。

### 阶段 2：后端修改

Backend subagent 修改：

- 新增 Flyway 迁移 `source/xzs/src/main/resources/db/migration/V3__add_user_nick_name.sql`：
  - 给 `t_user` 增加 `nick_name varchar(255)`。
  - 用 `real_name` 或 `user_name` 初始化已有用户昵称，优先 `real_name`，为空则用 `user_name`。
- 同步更新 `sql/xzs-postgresql.sql` 的 `t_user` 建表字段。
- `User` domain 增加 `nickName`。
- `UserMapper.xml` 增加 `nick_name` resultMap、column list、insert、selective insert/update、full update。
- 管理端用户创建/编辑 VM 和响应 VM 增加 `nickName`，允许管理员/老师维护昵称。
- 学生端 `UserResponseVM` 返回 `nickName`。
- 学生端 `UserUpdateVM` 改为只允许 `nickName`，删除或不再接收 `realName`、`age`、`sex`、`birthDay`、`phone`、`userLevel`。
- `/api/student/user/update` 只更新当前用户 `nickName` 和 `modifyTime`，不再让学生改真实姓名等字段。
- `/api/admin/user/edit` 保持“创建时密码必填、编辑时密码为空不改”的逻辑，并补测试覆盖。
- 新增 `POST /api/student/dashboard/class/ranking`：
  - 只统计当前登录学生 `classId` 所属班级。
  - 无班级时返回空列表或明确业务提示，推荐返回空列表。
  - 聚合字段：
    - `userId`
    - `userName`
    - `realName`
    - `nickName`
    - `rank`
    - `paperCount`
    - `questionCount`
    - `correctCount`
    - `accuracyRate`
    - `correctionCount`
    - `resubmitCount`
    - `lastSubmitTime`
    - `score`
  - 排序建议：
    - 综合分 `score = accuracyRate * 100 + ln(questionCount + 1) * 8 + correctionCount * 2 - resubmitCount`
    - `score` 相同按 `accuracyRate`、`questionCount`、`lastSubmitTime` 排序。
  - 统计来源：
    - 答题：`t_exam_paper_answer`，按 `create_user` 聚合，班级用 `coalesce(answer.class_id, user.class_id)`。
    - 改错：`t_question_correction_record`，按 `user_id` 聚合，班级用记录 `class_id` 或用户 `class_id`。

后端功能测试：

- 管理端编辑已有用户时，提交空密码后：
  - 数据库原密码 hash 不变。
  - 使用旧密码仍能登录。
- 学生调用 `/api/student/user/update` 修改昵称后：
  - `t_user.nick_name` 改变。
  - `real_name`、`phone`、`age`、`sex`、`birth_day`、`user_level` 不改变。
  - `/api/student/user/current` 返回新昵称和原真实姓名。
- 直接构造请求尝试给 `/api/student/user/update` 传 `realName`：
  - 真实姓名不改变。
- 班级排行榜：
  - 同班多个学生有答卷时，接口只返回同班学生。
  - 正确率等于 `sum(question_correct) / sum(question_count)`。
  - 改错次数等于改错记录数，重提次数等于 `sum(resubmit_count)`。
  - 当前学生无班级时返回空列表。

### 阶段 3：前端修改

Frontend subagent 修改：

- 管理端 `UserEditView.vue`：
  - 密码输入框 placeholder 改为“留空则不修改密码”。
  - 编辑提交时，密码为空或全空白则不带 `password` 字段。
  - 新增昵称字段，管理员/老师可以维护。
- API client：
  - `StudentUserInfo` 增加 `nickName`。
  - `StudentUserUpdateRequest` 改为只包含 `nickName`。
  - 删除学生端消息相关 API 导出，或至少停止在学生端使用。
  - 增加 `getClassRanking()` 对应 `/api/student/dashboard/class/ranking`。
- 学生端 `ShellLayout.vue`：
  - 右上角显示 `nickName || realName || userName`。
  - 移除消息菜单和 Bell 消息按钮。
- 学生端 router：
  - 删除 `/user/message` 路由。
- 学生端 user store：
  - 移除 `messageCount`、`initMessageCount` 和消息 API 依赖。
- 删除或停止引用 `UserMessageView.vue`。
- 学生个人中心：
  - 改成只保留“修改个人信息”区域。
  - 显示用户名、真实姓名、班级等只读信息。
  - 只允许编辑昵称。
  - 保存后刷新 store 中当前用户信息。
- 班级排行榜：
  - 新增页面或 dashboard 模块，推荐新增 `/ranking/class` 页面，同时在首页展示前 5 名入口。
  - 页面展示：
    - 前三名视觉突出。
    - “我的排名”固定展示。
    - 正确率、答题数、改错提交数、重提次数。
    - 与上一名差距提示，例如“距离上一名还差 12 题”或“正确率差 3.2%”。
  - 空班级、无数据、接口失败都有明确状态。

前端功能测试：

- 管理端编辑用户：
  - 打开已有用户编辑页，密码框为空提交。
  - 保存后重新登录该账号，旧密码仍可用。
  - 若输入新密码提交，旧密码失效，新密码可用。
- 学生端顶部用户显示：
  - 登录后右上角显示昵称。
  - 昵称为空时显示真实姓名；真实姓名为空时显示用户名。
- 学生个人中心：
  - 页面上没有真实姓名、年龄、性别、生日、手机的可编辑输入框。
  - 修改昵称保存后，右上角名字和个人中心展示同步更新。
  - 刷新页面后昵称仍正确显示。
- 消息版块：
  - 顶部菜单没有“消息”。
  - 右上角没有消息 Bell。
  - 访问 `/#/user/message` 不再进入消息页，应进入 404 或跳转到有效页面。
- 班级排行榜：
  - 有测试数据时能看到同班同学排行。
  - 排行榜不展示其他班学生。
  - 正确率、答题数、改错次数与后端数据一致。
  - 空数据时显示空状态而不是白屏。

### 阶段 4：整体验收

主线程执行：

- 后端单元/集成测试：
  - `cd D:\workspace\xzs\source\xzs`
  - `mvn test -DskipTests=false`
- 前端类型和构建：
  - `cd D:\workspace\xzs\frontend`
  - `pnpm typecheck`
  - `pnpm build:student`
  - `pnpm build:admin`
- 启动本地后端和前端，执行功能验收：
  - 管理端用户编辑空密码不改。
  - 学生端个人中心只能改昵称。
  - 首页右上角显示名字。
  - 消息入口消失。
  - 班级排行榜按同班数据展示并且统计口径正确。

检查点：

- 验证失败时不提交。
- 如果失败原因属于 subagent 负责范围，交回对应 subagent 修复。
- 如果失败原因是接口契约不一致，由主线程协调后再分派修复。

## 产出

- 本 harness 文档。
- 后端数据库迁移、接口、VM、Mapper、测试改动。
- 前端管理端、学生端、API client 改动。
- 验证记录。
- 一个统一 Git 提交和 push。

## 失败处理

- 如果数据库迁移失败：
  - 停止前端继续集成。
  - 修复迁移和 Mapper 后重新运行后端测试。
- 如果前后端字段不一致：
  - 以后端接口契约为准，修正 API client 和页面。
- 如果排行榜统计慢：
  - 先保留实时 SQL 聚合。
  - 后续再评估缓存或统计表，不在本次引入。
- 如果消息后端删除影响管理端：
  - 本次不删除后端消息能力，只移除学生端入口。
- 如果 subagent 修改范围冲突：
  - 主线程停止整合，明确冲突文件，要求其中一个 subagent 重新基于当前文件调整。
