# 现代前端迁移工作区结构

`frontend/` 是 Vue 3 + Vite Web 前端工作区，当前承载学生端和管理端源码、默认生产构建和共享包。学生端后端 `/student` 静态入口来自 `frontend/apps/student`，管理端后端 `/admin` 静态入口来自 `frontend/apps/admin`；旧 Vue 2 Web 源码目录已删除，不再保留新旧并行入口。

当前结构：

```text
frontend/
├── package.json
├── pnpm-lock.yaml
├── pnpm-workspace.yaml
├── tsconfig.base.json
├── apps/
│   ├── student/
│       ├── index.html
│       ├── vite.config.ts
│       ├── public/
│       └── src/
│           ├── layouts/
│           ├── router/
│           ├── stores/
│           ├── styles/
│           └── views/
│   └── admin/
│       ├── index.html
│       ├── vite.config.ts
│       ├── public/
│       └── src/
│           ├── components/
│           ├── layouts/
│           ├── router/
│           ├── stores/
│           ├── styles/
│           └── views/
├── packages/
│   ├── api-client/
│   ├── config/
│   ├── question-renderer/
│   └── shared/
└── scripts/
    ├── build-student.ps1
    ├── dev-student.ps1
    ├── verify-admin-ui-screenshots.mjs
    ├── verify-student-paper-readonly.ps1
    ├── verify-student-submit-edit-strict.ps1
    ├── verify-student-auth.ps1
    └── verify-student-ui-screenshots.mjs
```

## 当前职责

- `apps/student`：Vue 3 + Vite 学生端默认生产构建实现，开发端口 `8001`，构建输出目录为 `student`，静态资源目录为 `static`。
- `apps/admin`：Vue 3 + Vite 管理端默认生产构建实现，开发端口 `8002`，构建输出目录为 `admin`，覆盖登录、Dashboard、用户、学科、题库、试卷、任务、智能训练、答卷、消息、日志和个人资料模块。
- `apps/admin/public/admin/components/ueditor`：管理端 Vue 3 迁移期保留的 UEditor 静态资源，用于历史题库 HTML 和公式插件兼容；图片上传入口已关闭。
- `packages/api-client`：API 请求封装，覆盖登录、登出、当前用户、学生端考试链路、管理端 Dashboard、用户、学科、题库、试卷、任务、智能训练、答卷、消息、日志和个人资料接口。
- `packages/question-renderer`：题目 Markdown、历史 HTML、公式、代码高亮和安全清理的独立渲染包。
- `packages/shared`：迁移期共享工具和类型的起始包。
- `packages/config`：迁移期共享配置包，后续承载 ESLint、Prettier、Vite 和 TypeScript 公共配置。
- `scripts`：现代前端工作区的启动、构建、接口验证和截图验证脚本。

## 常用命令

从仓库根目录运行：

```powershell
.\frontend\scripts\dev-student.ps1
```

```powershell
.\frontend\scripts\build-student.ps1
```

认证链路验证需要后端和 Vite dev server 已启动：

```powershell
.\frontend\scripts\verify-student-auth.ps1
```

学生端试卷只读链路验证需要后端和 Vite dev server 已启动：

```powershell
.\frontend\scripts\verify-student-paper-readonly.ps1
```

如果当前测试数据应固定包含已完成记录和错题记录，可以开启严格只读验证：

```powershell
.\frontend\scripts\verify-student-paper-readonly.ps1 -RequireCompleteRecord -RequireWrongQuestion
```

学生端真实浏览器截图验证需要后端和 Vite dev server 已启动，截图输出到 `.tmp\playwright\student-ui`：

```powershell
Set-Location frontend
pnpm verify:student-ui
```

学生端真实提交/批改严格验证需要后端已启动，默认使用 PostgreSQL 容器 `xzs-postgres` 和试卷 `PaperId=2`，脚本会自动清理临时答卷：

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1
```

如果要验证真实主观题待批改链路，使用临时简答题试卷模式：

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1 -UseTemporarySubjectivePaper
```

如果要同时让 `/edit` 截图变成必验项，需要后端和 Vite dev server 都已启动：

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1 -UseTemporarySubjectivePaper -RunScreenshotStrict
```

截图验证默认使用 `XZS_EXAM_PAPER_ID=2` 和 `XZS_FORMULA_PAPER_ID=8`；如果要把查看试卷、批改页和错题详情变成必验项，运行前设置：

```powershell
$env:XZS_REQUIRE_COMPLETE_RECORD = "true"
$env:XZS_REQUIRE_PENDING_RECORD = "true"
$env:XZS_REQUIRE_WRONG_QUESTION = "true"
pnpm verify:student-ui
```

题目渲染包单元测试：

```powershell
pnpm --filter @xzs/question-renderer test
```

管理端开发服务：

```powershell
pnpm --dir frontend --filter @xzs/admin dev
```

管理端构建：

```powershell
pnpm --dir frontend --filter @xzs/admin build
```

管理端截图验证需要后端已启动：

```powershell
pnpm --dir frontend verify:admin-ui
```

该验证现在会创建并清理临时题，覆盖管理端登录、Dashboard、用户、学科、题库、试卷、任务、智能训练、答卷、消息、日志、个人资料、UEditor 加载、题目保存回读和退出。

管理端后端 static 入口验证需要后端已打包并启动：

```powershell
.\scripts\verify-admin-static.ps1
```

或进入 `frontend` 后运行：

```powershell
pnpm --filter @xzs/student dev
```

```powershell
pnpm --filter @xzs/student build
```

## 生产入口

- `scripts/build-student.ps1` 默认使用 `pnpm --filter @xzs/student run build` 构建 Vue 3 学生端。
- `scripts/build-admin.ps1` 默认使用 `pnpm --filter @xzs/admin run build` 构建 Vue 3 管理端。
- `scripts/sync-web-static.ps1` 默认把 `frontend/apps/student/student` 和 `frontend/apps/admin/admin` 同步到 `source/xzs/src/main/resources/static`。
- 后端 jar 内 `/student/index.html` 由 Vue 3 + Vite 产物提供。
- 后端 jar 内 `/admin/index.html` 由 Vue 3 + Vite 产物提供。

## 迁移约束

- 不新增 `/student-v3`、`/admin-v3` 这类长期并行入口。
- 学生端和管理端生产入口已经切换到 Vue 3 + Vite，旧 Vue 2 Web 工程已删除。
- 不再新增或恢复 Vue CLI 生产构建入口。
- 新的题目渲染、API client、UI 组件应优先沉淀到 `packages/`，避免散落在页面中。
