# 前端覆盖式重构阶段 0 基线报告

## 基线范围

本报告冻结 Vue 3 + Vite 覆盖式重构前的当前系统状态，用于后续阶段验收对比。阶段 0 不改变业务代码，只记录构建、运行、接口、静态资源、题库数据和发布入口现状。

- 日期：2026-07-04
- 分支：`master`
- 基线提交：`c4169058`
- 迁移路线文档：`docs/frontend-modernization-migration-roadmap.md`
- 构建测量原始结果：`.tmp/benchmarks/frontend-baseline-build-20260704-165648.json`

## 服务状态基线

当前启动方式：

```powershell
.\start.ps1
```

启动结果：

- 应用 PID：`3428`
- Admin：`http://localhost:8000/admin/index.html`
- Student：`http://localhost:8000/student/index.html`
- Database：`localhost:15432/xzs`
- Runtime logs：`.tmp/runtime`

HTTP 可用性：

| 地址 | 状态 |
| --- | ---: |
| `/student/index.html` | 200 |
| `/admin/index.html` | 200 |

默认登录账号：

| 端 | 用户名 | 密码 |
| --- | --- | --- |
| 学生端 | `student` | `123456` |
| 管理端 | `admin` | `123456` |

## 构建耗时基线

命令：

```powershell
.\scripts\measure-build.ps1 -Phase admin,student,sync,backend -SkipInstall -OutputPath .\.tmp\benchmarks\frontend-baseline-build-20260704-165648.json
```

结果：

| 阶段 | 状态 | 耗时 |
| --- | --- | ---: |
| admin | Succeeded | 79.01s |
| student | Succeeded | 38.67s |
| sync | Succeeded | 6.16s |
| backend | Succeeded | 19.90s |
| 合计 | Succeeded | 143.74s |

构建过程中的主要警告：

- Dart Sass `legacy-js-api` 弃用警告。
- Sass `@import` 弃用警告。
- Element UI 主题 Sass 中 `slash-div`、`global-builtin`、`function-units` 弃用警告。
- admin 和 student 均触发 asset size / entrypoint size 警告。

## 静态资源体积基线

后端内置静态资源：

| 范围 | 文件数 | 体积 |
| --- | ---: | ---: |
| `static/admin` + `static/student` | 808 | 10.81 MiB |

按端和资源类型：

| 范围 | 文件数 | 体积 |
| --- | ---: | ---: |
| admin JS | 38 | 3257.31 KiB |
| admin CSS | 19 | 302.60 KiB |
| student JS | 17 | 1431.81 KiB |
| student CSS | 15 | 294.36 KiB |

学生端 Top JS：

| 文件 | 体积 |
| --- | ---: |
| `chunk-vendors.3fb799d7.js` | 723.90 KiB |
| `chunk-8b0b1c96.a552debd.js` | 514.40 KiB |
| `index.e930cd61.js` | 97.42 KiB |
| `chunk-588b28eb.d6d641e6.js` | 17.83 KiB |
| `chunk-352e2714.a6e77231.js` | 10.86 KiB |

管理端 Top JS：

| 文件 | 体积 |
| --- | ---: |
| `chunk-vendors.131afb25.js` | 724.74 KiB |
| `chunk-bcf0d4b8.1fc14fa2.js` | 578.48 KiB |
| `chunk-97e0c72e.fba7eb6c.js` | 515.32 KiB |
| `chunk-5ca44f22.9184db4b.js` | 259.86 KiB |
| `chunk-2178322b.d3b36732.js` | 258.05 KiB |

## 静态资源压缩响应基线

请求带 `Accept-Encoding: gzip` 时，以下 JS 响应没有 `Content-Encoding`，即当前未 gzip 传输：

| URL | 状态 | Content-Encoding | 响应长度 | Cache-Control |
| --- | ---: | --- | ---: | --- |
| `/student/static/js/chunk-8b0b1c96.a552debd.js` | 200 | 空 | 526749 | `public, max-age=31536000` |
| `/student/static/js/chunk-vendors.3fb799d7.js` | 200 | 空 | 741275 | `public, max-age=31536000` |
| `/admin/static/js/chunk-97e0c72e.fba7eb6c.js` | 200 | 空 | 527690 | `public, max-age=31536000` |
| `/admin/static/js/chunk-vendors.131afb25.js` | 200 | 空 | 742132 | `public, max-age=31536000` |

迁移后的后端或静态服务必须显式验证 JS/CSS/JSON/HTML 压缩响应。

## 学生端接口耗时基线

登录用户：`student`

| 接口 | 请求说明 | 耗时 | 响应大小 |
| --- | --- | ---: | ---: |
| `/api/student/education/subject/list` | 学科列表 | 83ms | 335 bytes |
| `/api/student/exam/paper/pageList` | `subjectId=1,paperType=1` | 209ms | 497 bytes |
| `/api/student/exam/paper/pageList` | `subjectId=3,paperType=1`，当前空列表 | 17ms | 320 bytes |
| `/api/student/exam/paper/select/8` | 25 题智能训练试卷 | 294ms | 15384 bytes |

试卷详情多次测量：

| 试卷 ID | 题量来源 | 响应大小 | 耗时样本 |
| --- | --- | ---: | --- |
| 2 | 数据库关联 5 题 | 5706 bytes | 132ms, 103ms, 139ms |
| 7 | 数据库关联 20 题 | 13202 bytes | 218ms, 261ms, 450ms |
| 8 | 数据库关联 25 题 | 15384 bytes | 509ms, 375ms, 598ms |

阶段 0 未调用 `answerSubmit`，避免产生新的考试提交记录。后续 E2E 测试应使用专用测试账号或可重置数据集测交卷路径。

## 数据库样本基线

题目内容表：

| 指标 | 数量 |
| --- | ---: |
| `t_text_content` 总数 | 2129 |
| 包含 `$` 的内容 | 751 |
| 同时包含 `<p>` 和 `$` 的历史 HTML/公式内容 | 751 |

当前可见试卷：

| 试卷 ID | 名称 | subject_id | paper_type |
| ---: | --- | ---: | ---: |
| 2 | 测试 | 1 | 1 |
| 5 | 智能训练-GESP 1级-2026-07-03 17:29:58 | 1 | 7 |
| 6 | 智能训练-GESP 1级-2026-07-03 17:30:24 | 1 | 7 |
| 7 | 智能训练-GESP 1级-2026-07-03 17:54:26 | 1 | 7 |
| 8 | 智能训练-GESP 1级-2026-07-03 22:01:40 | 1 | 7 |

## 当前关键页面清单

学生端：

- 登录：`/login`
- 注册：`/register`
- 首页：`/index`
- 试卷中心：`/paper/index`
- 答题：`/do?id={paperId}`
- 批改/编辑答卷：`/edit`
- 查看答卷：`/read`
- 考试记录：`/record/index`
- 智能训练：`/training/index`
- 错题本：`/question/index`
- 个人中心：`/user/index`
- 消息中心：`/user/message`

管理端需要在阶段 6 前从路由表固化完整页面清单，至少覆盖：

- 登录和 Dashboard
- 用户管理
- 学科管理
- 题目列表
- 单选、多选、判断、填空、简答题编辑
- 试卷管理
- 考试记录和阅卷
- 消息、任务、日志
- 图表、Excel、代码编辑器相关页面

## 覆盖前安全 tag 流程

创建覆盖前 tag 之前必须确认：

1. `git status --short` 无未提交业务代码。
2. 当前 commit 已记录到基线报告。
3. 构建产物已同步到 `source/xzs/src/main/resources/static/admin` 和 `source/xzs/src/main/resources/static/student`。
4. 服务可启动，`/student/index.html` 和 `/admin/index.html` 返回 200。
5. 数据库样本版本已记录。

推荐 tag：

```powershell
git tag vue2-baseline-20260704 c4169058
git push origin vue2-baseline-20260704
```

该 tag 只作为覆盖前代码历史保护点，不作为线上并行版本入口。

