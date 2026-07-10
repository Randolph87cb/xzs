# 班级与教师管理改造方案

## 目标

在现有信息学客观题一本通中加入班级概念，并支持老师负责多个班级。老师可以在后台新增班级、新增学生、维护学生与班级的绑定关系，并仅管理自己负责班级内学生的练习、答卷和改错审核数据。管理员保留全局管理能力。

## 业务规则

- 一个学生只属于一个班级。
- 一个老师可以负责多个班级。
- 一个班级只设置一个负责老师。
- 老师可以新增班级，新增学生，并把学生绑定到自己负责的班级。
- 老师不能管理其他老师负责的班级、学生、练习记录和改错记录。
- 管理员可以管理所有班级、老师、学生和学习数据。

## 数据模型

### 角色

扩展 `RoleEnum`：

```java
STUDENT(1, "STUDENT"),
TEACHER(2, "TEACHER"),
ADMIN(3, "ADMIN");
```

后台登录权限允许 `ADMIN` 和 `TEACHER` 进入 `/api/admin/**`，但具体业务接口必须继续做数据范围校验。

### 班级表

新增 `t_class`：

```sql
CREATE TABLE "public"."t_class" (
  "id" serial PRIMARY KEY,
  "name" varchar(255) NOT NULL,
  "grade_level" int4,
  "teacher_id" int4 NOT NULL,
  "status" int4 NOT NULL DEFAULT 1,
  "create_time" timestamp(6),
  "modify_time" timestamp(6),
  "deleted" bool NOT NULL DEFAULT false
);

CREATE INDEX "idx_class_teacher" ON "public"."t_class" ("teacher_id", "deleted");
CREATE INDEX "idx_class_grade" ON "public"."t_class" ("grade_level", "deleted");
```

### 用户表

扩展 `t_user`：

```sql
ALTER TABLE "public"."t_user" ADD COLUMN "class_id" int4;
CREATE INDEX "idx_user_class_role" ON "public"."t_user" ("class_id", "role", "deleted");
```

规则：

- `role = STUDENT` 时，`class_id` 表示学生所属班级。
- `role = TEACHER` 时，不使用 `class_id`；通过 `t_class.teacher_id` 反查负责班级。
- `role = ADMIN` 时，不使用 `class_id`。

### 历史业务表冗余班级

建议扩展：

```sql
ALTER TABLE "public"."t_exam_paper_answer" ADD COLUMN "class_id" int4;
ALTER TABLE "public"."t_exam_paper_question_customer_answer" ADD COLUMN "class_id" int4;
ALTER TABLE "public"."t_question_correction_record" ADD COLUMN "class_id" int4;

CREATE INDEX "idx_exam_paper_answer_class" ON "public"."t_exam_paper_answer" ("class_id", "create_time");
CREATE INDEX "idx_customer_answer_class" ON "public"."t_exam_paper_question_customer_answer" ("class_id", "create_time");
CREATE INDEX "idx_question_correction_class_status" ON "public"."t_question_correction_record" ("class_id", "review_status", "submit_time");
```

冗余 `class_id` 的目的：学生转班后，历史练习和改错记录仍保留提交时所在班级的统计口径。

### 任务发布

第一阶段建议在 `t_task_exam` 增加 `class_id`：

```sql
ALTER TABLE "public"."t_task_exam" ADD COLUMN "class_id" int4;
CREATE INDEX "idx_task_exam_class" ON "public"."t_task_exam" ("class_id", "deleted");
```

规则：

- `class_id` 为空时，兼容原有按 `grade_level` 发布的任务。
- `class_id` 不为空时，表示班级任务。
- 老师只能创建自己负责班级的班级任务。
- 管理员可以创建年级任务或班级任务。

未来如果需要一个任务同时发布给多个班级，再扩展为 `t_task_exam_class` 关联表；第一阶段不引入该复杂度。

## 权限矩阵

| 功能 | 管理员 | 老师 |
| --- | --- | --- |
| 新增/编辑班级 | 所有班级，可指定老师 | 可以新增班级，负责老师强制为自己 |
| 查看班级 | 所有班级 | 自己负责的班级 |
| 新增学生 | 可以 | 可以 |
| 编辑学生 | 所有学生 | 自己班级学生 |
| 绑定学生班级 | 任意班级 | 只能绑定到自己负责的班级 |
| 查看答卷和练习 | 全部 | 自己班级学生 |
| 改错审核 | 全部 | 自己班级学生 |
| 布置任务 | 全部班级或年级 | 自己负责的班级 |
| 管理老师和管理员 | 可以 | 不可以 |

## 后端改造

### 数据范围服务

新增 `ClassScopeService`，集中处理老师数据范围：

```java
boolean isAdmin(User user);
boolean isTeacher(User user);
List<Integer> teacherClassIds(User teacher);
boolean canManageClass(User user, Integer classId);
boolean canManageStudent(User user, Integer studentId);
void requireClassAccess(User user, Integer classId);
void requireStudentAccess(User user, Integer studentId);
```

所有涉及老师范围的数据访问必须走该服务，不能只依赖前端筛选。

### 班级管理接口

新增 `/api/admin/class`：

- `POST /page`
- `POST /select/{id}`
- `POST /edit`
- `POST /delete/{id}`
- `POST /options`

规则：

- 管理员分页返回全部班级。
- 老师分页只返回自己负责的班级。
- 老师新增班级时，`teacherId` 强制设置为当前用户。
- 老师编辑或删除班级时，必须校验该班级属于自己。

### 用户管理接口

改造 `/api/admin/user`：

- 老师可以创建和编辑 `role = STUDENT` 的用户。
- 老师不能创建或编辑老师、管理员。
- 老师创建学生时必须传 `classId`。
- 老师传入的 `classId` 必须属于自己负责的班级。
- 老师查询学生列表时，只返回自己负责班级内的学生。
- 管理员保留现有全局能力，并可以创建老师账号。

### 答卷和练习数据

改造 `ExamPaperAnswerMapper.adminPage`：

- 管理员不加班级限制。
- 老师加 `class_id in 当前老师负责班级`。
- 旧数据 `class_id` 为空时，可临时通过 `t_user.class_id` 兼容查询。

学生提交答卷时写入当前学生 `class_id` 到：

- `t_exam_paper_answer.class_id`
- `t_exam_paper_question_customer_answer.class_id`

### 改错审核

改造后台 `QuestionCorrectionController`：

- 列表按班级范围过滤。
- 详情查询必须校验班级范围。
- 审核保存必须再次校验班级范围。

学生提交改错时写入当前学生 `class_id` 到 `t_question_correction_record.class_id`。

### 任务管理

改造 `TaskExamService` 和 `TaskExamMapper`：

- 老师创建任务时必须选择自己负责的 `classId`。
- 老师查询任务只返回自己班级任务。
- 管理员可查询和创建所有任务。
- 学生端任务列表查询支持班级任务，并兼容旧的年级任务。

## 前端改造

### 管理端菜单

管理员显示完整菜单。

老师显示：

- 班级管理
- 学生管理
- 任务管理
- 答卷列表
- 改错审核
- 个人信息

### 页面

新增或改造：

- 班级列表页和班级编辑页。
- 学生编辑页增加班级选择。
- 用户管理增加老师列表。
- 答卷列表增加班级筛选。
- 改错审核增加班级筛选。
- 任务编辑增加发布班级。

老师端页面约束：

- 新增班级不显示负责老师选择，默认绑定当前老师。
- 新增学生必须选择自己负责的班级。
- 班级筛选项只展示当前老师负责的班级。

## Harness 执行结构

### 目标

稳定完成班级与教师管理第一阶段改造，使老师可以管理自己负责的多个班级、学生、任务、答卷和改错审核数据。

### 适用范围

适用于本次班级/教师权限功能改造，包括数据库脚本、Spring Boot 后端、Vue 3 管理端和必要的学生端任务查询调整。

不适用于：

- 多老师共同负责一个班级。
- 一个学生同时加入多个班级。
- 班级历史变更审计。
- 多班级批量发布同一个任务。

### 输入

- 本文档中的业务规则和权限矩阵。
- 当前项目结构和 `AGENTS.md` 约束。
- 现有后端用户、答卷、任务、改错审核接口。
- 现有管理端 Vue 3 + Vite 工作区。

### 执行流程

1. 主线程创建和维护本文档，只负责调度。
2. 实现 subagent 串行执行功能改造。
3. 主线程审阅实现 subagent 的变更摘要和工作区状态。
4. 验证 subagent 独立执行构建、测试和关键代码检查。
5. 主线程汇总实现与验证结果，按项目规则提交和推送。

实现与验证必须分离。验证 subagent 不应继续实现新功能；如果发现问题，应报告给主线程，由主线程再调度实现 subagent 修复。

### 角色分工

主线程：

- 维护方案文档。
- 创建和调度 subagent。
- 决定是否继续、返工、提交和推送。
- 不直接做功能代码修改。

实现 subagent：

- 修改数据库脚本、后端、前端源码。
- 遵守项目现有结构和命名风格。
- 不提交 Git，除非主线程明确要求。
- 输出变更摘要、风险点和建议验证命令。

验证 subagent：

- 不做功能修改。
- 运行后端和前端验证命令。
- 检查关键权限路径是否有后端数据范围约束。
- 输出验证结果、失败原因和残余风险。

### 检查点

- 文档检查点：本文档包含目标、范围、输入、流程、角色、检查点、产出、失败处理和 Git 策略。
- 实现检查点：代码能编译或至少通过静态类型检查；关键权限路径均有后端范围校验。
- 验证检查点：验证命令完成，失败项有明确原因；未验证项不得描述为已通过。
- 提交检查点：只提交本次相关改动，不回滚既有无关改动。

### 产出

- 方案文档：`docs/class-teacher-management-plan.md`
- 数据库脚本改动：`sql/xzs-postgresql.sql`
- 后端班级、老师、学生、任务、答卷、改错审核相关改动。
- 管理端班级和老师权限相关页面改动。
- 验证报告。
- Git 提交和推送结果。

### 失败处理

- 信息不足：主线程暂停并向用户确认。
- 实现失败：实现 subagent 输出失败点，主线程决定是否缩小范围或重新调度。
- 验证失败：验证 subagent 只报告问题，不直接修复；主线程再调度实现 subagent。
- Git 冲突或远端推送失败：不强行覆盖，报告当前状态和下一步建议。

### Git 策略

按项目规则，完成修改后默认执行 `git add`、`git commit`、`git push`。提交信息使用中文。提交前必须查看 `git status`，避免把无关既有改动混入本次提交。

当前工作区如存在非本次产生的静态构建产物改动，主线程和 subagent 均不得回滚；提交时只纳入本次相关文件。
