# 前端覆盖式重构阶段 4 学生端核心子闭环报告

## 阶段范围

阶段 4 的完整目标是迁移学生端核心业务。本阶段先完成一个可验证的核心子闭环：

```text
登录 -> 试卷中心 -> 取卷答题 -> 交卷入口 -> 考试记录
```

同时补充智能训练入口、查看试卷、错题本和首页任务/试卷入口。个人中心、消息中心和批改试卷详情页还未迁移。

- 日期：2026-07-04
- 基于提交：`399eb97f`
- 应用：`frontend/apps/student`

## 已落地内容

新增学生端业务 API：

- `getSubjectList`
- `getExamPaperPage`
- `getExamPaperDetail`
- `submitExamPaperAnswer`
- `getExamRecordPage`
- `createSmartTrainingPaper`

新增页面：

- `PaperListView`：试卷中心，支持学科切换、固定/时段试卷切换、分页。
- `ExamDoView`：答题页，支持单选、多选、判断、填空、简答、倒计时、答题卡、提交。
- `RecordListView`：考试记录列表和选中记录摘要。
- `TrainingView`：智能训练创建并跳转答题。
- `ExamReadView`：查看已完成试卷。
- `QuestionErrorView`：错题本列表和错题详情。
- `DashboardView`：首页任务中心、固定试卷和时段试卷入口。

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
现在也覆盖首页、任务、查看试卷、错题列表和错题详情接口。

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

## 构建与拆包

首次把答题页静态引入时，学生端主 JS 从约 `1043 kB` 增至约 `1801 kB`。已改为路由懒加载，答题页和渲染器独立拆包。

当前构建结果：

| 文件 | 体积 |
| --- | ---: |
| `student/index.html` | `1.24 kB`, gzip `0.67 kB` |
| 主 CSS | `357.89 kB`, gzip `48.11 kB` |
| 主 JS | `980.31 kB`, gzip `317.09 kB` |
| 题目渲染共享 JS | `741.74 kB`, gzip `235.41 kB` |
| 答题页 JS | `5.66 kB`, gzip `2.24 kB` |
| 查看试卷 JS | `2.25 kB`, gzip `1.22 kB` |
| 错题本 JS | `2.23 kB`, gzip `1.23 kB` |

主 JS 仍偏大，主要原因仍是 Element Plus 整包接入。后续应接入按需导入。

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

结果：通过。

开发服务：

```powershell
pnpm --filter @xzs/student dev -- --open false
```

结果：Vite ready in `357 ms`。

认证验证：

```powershell
.\frontend\scripts\verify-student-auth.ps1
```

结果：通过。

试卷只读验证：

```powershell
.\frontend\scripts\verify-student-paper-readonly.ps1
```

结果：通过，验证试卷 `paperId=2`。

## 未验证项

为避免污染本地考试记录，本次没有自动执行真实交卷接口 `answerSubmit`。答题提交页面逻辑已实现，后续应使用专用测试账号或可重置数据集验证交卷、重复提交和记录新增。

## 剩余工作

阶段 4 还剩：

- 批改试卷 `/edit`。
- 个人中心 `/user/index`。
- 消息中心 `/user/message`。
- 大试卷分批渲染或虚拟滚动。
- Element Plus 按需导入和进一步拆包。

## 阶段 4 子闭环结论

学生端核心子闭环已经具备可运行基础：可登录、可拉取首页任务和试卷列表、可进入答题页、题目内容使用新 renderer 渲染、可查看考试记录和已完成试卷、可查看错题本、可创建智能训练卷。该子闭环还不是完整阶段 4，不能进入阶段 5 覆盖切换。
