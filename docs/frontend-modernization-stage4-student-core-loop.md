# 前端覆盖式重构阶段 4 学生端核心子闭环报告

## 阶段范围

阶段 4 的完整目标是迁移学生端核心业务。本阶段先完成一个可验证的核心子闭环：

```text
登录 -> 试卷中心 -> 取卷答题 -> 交卷入口 -> 考试记录
```

同时补充智能训练入口、查看试卷、批改试卷、错题本、首页任务/试卷入口、个人中心和消息中心。

- 日期：2026-07-04
- 基于提交：`163dbe27`
- 应用：`frontend/apps/student`

## 已落地内容

新增学生端业务 API：

- `getSubjectList`
- `getExamPaperPage`
- `getExamPaperDetail`
- `submitExamPaperAnswer`
- `editExamPaperAnswer`
- `getExamRecordPage`
- `createSmartTrainingPaper`

新增页面：

- `PaperListView`：试卷中心，支持学科切换、固定/时段试卷切换、分页。
- `ExamDoView`：答题页，支持单选、多选、判断、填空、简答、倒计时、答题卡、提交，并按题号分批渲染题目。
- `RecordListView`：考试记录列表和选中记录摘要。
- `TrainingView`：智能训练创建并跳转答题。
- `ExamReadView`：查看已完成试卷。
- `ExamEditView`：批改待批改试卷，支持按题号定位、查看题目 Markdown/公式/代码渲染和分数选择。
- `QuestionErrorView`：错题本列表和错题详情。
- `DashboardView`：首页任务中心、固定试卷和时段试卷入口。
- `UserCenterView`：个人资料展示、资料编辑、头像上传和用户动态。
- `UserMessageView`：消息列表和展开标记已读。

新增组件和工具：

- `QuestionEditor`：答题交互组件，使用 `@xzs/question-renderer` 渲染题干和选项。
- `formatSeconds`
- `formatExamAnswerStatus`
- `formatExamAnswerStatusTag`

新增验证脚本：

```powershell
.\frontend\scripts\verify-student-paper-readonly.ps1
```

该脚本只读验证登录后的学科列表、试卷列表、试卷详情和考试记录，不提交试卷，不产生答题记录。
现在也覆盖首页、任务、用户动态、消息列表、查看试卷、错题列表和错题详情接口。

默认数据前提：

- 账号：`student / 123456`
- 学科：`SubjectId=1`
- 试卷类型：`PaperType=1`

严格模式：

```powershell
.\frontend\scripts\verify-student-paper-readonly.ps1 -RequireCompleteRecord -RequireWrongQuestion
```

开启后，如果缺少已完成记录或错题记录，脚本会失败，而不是跳过对应详情验证。

```powershell
pnpm verify:student-ui
```

该脚本使用 Playwright Chromium 做真实浏览器截图验证：登录、首页、试卷中心、答题页、公式渲染桌面/移动视口、考试记录、已完成试卷查看、错题本、个人中心和消息中心。若当前数据库存在待批改记录，会自动进入 `/edit` 截图；若不存在，会显式跳过 `/edit` 截图。

默认数据前提：

- 账号：`XZS_STUDENT_USERNAME=student`，`XZS_STUDENT_PASSWORD=123456`
- 普通答题卷：`XZS_EXAM_PAPER_ID=2`
- 公式测试卷：`XZS_FORMULA_PAPER_ID=8`

严格模式环境变量：

- `XZS_REQUIRE_COMPLETE_RECORD=true`：要求至少存在一条 `status=2` 的考试记录并截图 `/read`。
- `XZS_REQUIRE_PENDING_RECORD=true`：要求至少存在一条 `status=1` 的考试记录并截图 `/edit`。
- `XZS_REQUIRE_WRONG_QUESTION=true`：要求至少存在一条错题并验证错题详情渲染。

截图验证是冒烟验证：能发现白屏、路由失败、接口报错、关键 DOM 缺失和 KaTeX 未渲染；它只校验截图文件非空，不做像素级视觉回归。阶段 4 稳定验收需要可重置测试数据集提供普通试卷、公式试卷、已完成记录、待批改记录、错题和消息。

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1
```

该脚本验证真实变更链路：登录学生端、读取试卷、调用 `answerSubmit` 创建临时答卷、用数据库把临时答卷转为待批改状态、调用 `read` 读取批改 payload、调用 `edit` 完成批改，然后清理临时答卷、答题明细、临时文本内容和本次脚本产生的用户日志。默认使用 PostgreSQL 容器 `xzs-postgres` 和试卷 `PaperId=2`。

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1 -UseTemporarySubjectivePaper
```

该模式会临时插入一张包含简答题的固定试卷，调用 `answerSubmit` 后自然生成 `status=1` 待批改答卷，再完成读取、批改和清理。它比默认模式更接近真实业务数据，因为不再通过 SQL 把已有客观题答卷转换成待批改状态。

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1 -RunScreenshotStrict
```

开启后，脚本会在临时待批改记录存在时运行严格截图验证，因此 `/edit` 从条件覆盖变成必验覆盖。

## 关键实现说明

答题 payload 保持旧端结构：

```json
{
  "id": 2,
  "doTime": 300,
  "answerItems": [
    {
      "questionId": 1,
      "content": "A",
      "contentArray": [],
      "completed": true,
      "itemOrder": 1
    }
  ]
}
```

题型映射：

- 单选、判断：写入 `content`。
- 多选：写入 `contentArray`。
- 填空：按旧端逻辑使用 `prefix - 1` 写入 `contentArray`，无法解析时回退到显示顺序。
- 简答：写入 `content`。

题目渲染：

- 题干和选项均使用 `QuestionMarkdown`。
- `$N$`、HTML 包裹公式、代码块和 XSS 清理沿用阶段 3 的 `question-renderer`。

路由重载：

- `/do`、`/read`、`/edit` 均监听 query id 变化，同一路由切换不同试卷或答卷时会重新加载数据。
- 严格截图在 `/do?id=临时简答卷` 后切换到 `/do?id=8` 验证公式渲染，覆盖了同组件复用场景。

## 构建与拆包

首次把答题页静态引入时，学生端主 JS 从约 `1043 kB` 增至约 `1801 kB`。已改为路由懒加载，答题页和渲染器独立拆包；随后移除 Element Plus 整包注册，改为按需引入。

当前构建结果：

| 文件 | 体积 |
| --- | ---: |
| `student/index.html` | `1.36 kB`, gzip `0.68 kB` |
| 主 CSS | `22.13 kB`, gzip `3.99 kB` |
| 主 JS | `120.70 kB`, gzip `42.78 kB` |
| 题目渲染共享 JS | `741.71 kB`, gzip `235.38 kB` |
| 答题页 JS | `8.21 kB`, gzip `3.17 kB` |
| 查看试卷 JS | `2.31 kB`, gzip `1.24 kB` |
| 批改试卷 JS | `3.56 kB`, gzip `1.70 kB` |
| 错题本 JS | `2.28 kB`, gzip `1.24 kB` |
| 个人中心 JS | `124.21 kB`, gzip `36.72 kB` |

主 JS 已从按需引入前约 `981 kB` 降到约 `121 kB`。仍偏大的 chunk 主要是题目渲染共享包和 Element Plus 局部组件依赖，后续可继续做 renderer 内部拆包和 CSS 合并评估。

## 验证结果

单元测试：

```powershell
pnpm --filter @xzs/question-renderer test
```

结果：`1 passed, 9 passed`。

学生端构建：

```powershell
.\frontend\scripts\build-student.ps1
```

结果：通过，Element Plus 按需引入后 Vite reported `built in 8.90s`；根生产构建脚本缓存构建 reported `built in 4.24s`。

开发服务：

```powershell
pnpm --filter @xzs/student dev -- --open false
```

结果：Vite ready in `2831 ms`。

认证验证：

```powershell
.\frontend\scripts\verify-student-auth.ps1
```

结果：通过。覆盖登录前 `current=401`、登录、登录后 `current=1`、登出、登出后 `current=401`。

试卷只读验证：

```powershell
.\frontend\scripts\verify-student-paper-readonly.ps1
```

结果：通过，验证试卷 `paperId=2`。

严格只读验证：

```powershell
.\frontend\scripts\verify-student-paper-readonly.ps1 -RequireCompleteRecord -RequireWrongQuestion
```

结果：通过。

严格真实提交/批改验证：

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1 -UseTemporarySubjectivePaper
```

结果：通过，临时试卷 `paperId=13`、临时答卷 `answerId=13` 已自动清理。

严格真实提交/批改 + 截图验证：

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1 -UseTemporarySubjectivePaper -RunScreenshotStrict
```

结果：通过，临时试卷 `paperId=14`、临时答卷 `answerId=14` 已自动清理，生成 `/edit` 截图 `06c-exam-edit.png`。

截图验证：

```powershell
pnpm verify:student-ui
```

结果：通过。截图输出目录：

```text
D:\workspace\xzs\.tmp\playwright\student-ui
```

本次生成截图：

- `01-login.png`
- `02-dashboard.png`
- `03-paper-list.png`
- `04-exam-do.png`
- `05-exam-formula.png`
- `05b-exam-formula-mobile.png`
- `06-record-list.png`
- `06b-exam-read.png`
- `06c-exam-edit.png`
- `07-question-error.png`
- `08-user-center.png`
- `09-user-message.png`

普通截图脚本仍会在数据库缺少 `status === 1` 记录时跳过 `/edit`。严格组合验证通过 `verify-student-submit-edit-strict.ps1 -RunScreenshotStrict` 临时创建待批改记录，已覆盖 `/edit` 截图和真实批改提交。

构建 warning：

- `@vueuse/core` 的 `/* #__PURE__ */` 注释位置触发 Rolldown `INVALID_ANNOTATION`，来源于第三方包。
- 题目渲染共享 chunk 仍超过 500 kB，后续可继续处理 KaTeX、Markdown、DOMPurify 和代码高亮的更细粒度拆包。
- 构建存在 `PLUGIN_TIMINGS` 提示，按需组件插件在冷构建中占比较高。

## 未验证项

真实交卷接口 `answerSubmit` 和批改接口 `edit` 已通过临时简答题试卷验证。脚本会创建专用临时试卷和简答题，使提交自然生成 `status=1` 待批改记录，并在验证后清理试卷、题目、答卷、明细、临时文本和本次脚本日志。

## 剩余工作

阶段 4 原剩余项已处理：

- 大试卷性能：答题页首屏先渲染前 8 题，后续题目通过 `requestIdleCallback` 或短延时分批挂载；点击答题卡会立即补渲染到目标题号再滚动。
- 拆包：学生端移除 `app.use(ElementPlus)` 整包注册，改用 `unplugin-auto-import` 和 `unplugin-vue-components` 对 Element Plus 组件与样式按需导入。
- 个人中心低频能力：补齐资料编辑、头像上传和对应截图验证断言。

## 阶段 4 子闭环结论

学生端核心子闭环已经具备可运行基础：可登录、可拉取首页任务和试卷列表、可进入答题页、题目内容使用新 renderer 渲染、可查看考试记录和已完成试卷、可进入待批改试卷页面、可查看错题本、可打开个人中心和消息中心、可创建智能训练卷。真实提交/批改接口、自然待批改数据和 `/edit` 截图已经进入严格验证；大试卷分批渲染、Element Plus 按需拆包和个人中心编辑能力已补齐，可以进入阶段 5 学生端覆盖切换。
