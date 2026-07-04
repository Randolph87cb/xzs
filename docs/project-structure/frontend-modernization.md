# 现代前端迁移工作区结构

`frontend/` 是 Vue 3 + Vite 覆盖式重构的迁移工作区，用于阶段性实现并验收新的学生端和后续管理端。它不是长期生产并行入口；迁移完成后会覆盖旧的 `source/vue/xzs-student` 和 `source/vue/xzs-admin`，或收敛为最终唯一前端结构。

当前阶段已建立学生端骨架：

```text
frontend/
├── package.json
├── pnpm-lock.yaml
├── pnpm-workspace.yaml
├── tsconfig.base.json
├── apps/
│   └── student/
│       ├── index.html
│       ├── vite.config.ts
│       ├── public/
│       └── src/
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
    └── verify-student-auth.ps1
```

## 当前职责

- `apps/student`：Vue 3 + Vite 学生端迁移实现，开发端口 `8001`，构建输出目录为 `student`，静态资源目录为 `static`。
- `packages/api-client`：迁移期 API 请求封装，当前覆盖登录、登出、当前学生用户和消息数量接口。
- `packages/question-renderer`：题目 Markdown、历史 HTML、公式、代码高亮和安全清理的独立渲染包。
- `packages/shared`：迁移期共享工具和类型的起始包。
- `packages/config`：迁移期共享配置包，后续承载 ESLint、Prettier、Vite 和 TypeScript 公共配置。
- `scripts`：现代前端工作区的启动和构建脚本。

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

题目渲染包单元测试：

```powershell
pnpm --filter @xzs/question-renderer test
```

或进入 `frontend` 后运行：

```powershell
pnpm --filter @xzs/student dev
```

```powershell
pnpm --filter @xzs/student build
```

## 迁移约束

- 不新增 `/student-v3`、`/admin-v3` 这类长期并行入口。
- 学生端验收后直接覆盖旧学生端生产入口。
- 管理端验收后直接覆盖旧管理端生产入口。
- 新的题目渲染、API client、UI 组件应优先沉淀到 `packages/`，避免散落在页面中。
