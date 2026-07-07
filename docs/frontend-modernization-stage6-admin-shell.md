# 前端覆盖式重构阶段 6 管理端基础壳报告

## 阶段范围

阶段 6 对应管理端 Vue 3 + Vite 基础迁移，目标是跑通管理端最小可验证闭环：

```text
登录 -> 管理端布局 -> Dashboard -> 学科列表 -> 退出
```

- 日期：2026-07-04
- 应用：`frontend/apps/admin`
- 开发端口：`8002`
- 构建输出：`frontend/apps/admin/admin`

## 已落地内容

新增管理端 Vue 3 + Vite 应用：

- `frontend/apps/admin/package.json`
- `frontend/apps/admin/vite.config.ts`
- `frontend/apps/admin/src/main.ts`
- `frontend/apps/admin/src/router/index.ts`
- `frontend/apps/admin/src/stores/user.ts`
- `frontend/apps/admin/src/layouts/AdminLayout.vue`

新增页面：

- `LoginView`：复用 `/api/user/login`，成功后进入 `/dashboard`。
- `DashboardView`：复用 `/api/admin/dashboard/index` 展示四个核心计数和近 30 日趋势。
- `SubjectListView`：复用 `/api/admin/education/subject/page` 展示学科分页列表。
- `NotFoundView`：基础 404 页面。

新增管理端 API：

- `getCurrentAdminUser`
- `getAdminUserPage`
- `getAdminDashboardIndex`
- `getAdminSubjectPage`

新增验证脚本：

```powershell
pnpm --dir frontend verify:admin-ui
```

该脚本使用 Playwright Chromium 做真实浏览器验证，覆盖登录、Dashboard、学科列表和退出，并输出截图到：

```text
D:\workspace\xzs\.tmp\playwright\admin-ui
```

## 关键实现说明

管理端旧系统没有后端下发菜单，菜单来源是静态路由。本阶段沿用静态菜单策略，先覆盖：

- `/dashboard`
- `/education/subject/list`

登录态：

- 登录接口仍为 `/api/user/login`。
- 当前用户接口为 `/api/admin/user/current`。
- 前端继续使用 `adminUserName` cookie 保存用户名。
- 请求层继续通过 `code=401/502` 跳转登录。

构建：

- Vite `base: './'`。
- 构建输出目录 `admin`。
- 静态资源目录 `static`。
- Element Plus 使用自动按需导入。

## 验证结果

管理端构建：

```powershell
pnpm --dir frontend --filter @xzs/admin build
```

结果：通过，Vite reported `built in 5.18s`。

管理端开发服务：

```powershell
pnpm --dir frontend --filter @xzs/admin dev -- --open false
```

结果：通过，Vite ready in `584 ms`。

管理端截图验证：

```powershell
pnpm --dir frontend verify:admin-ui
```

结果：通过。生成截图：

- `01-login.png`
- `02-dashboard.png`
- `03-subject-list.png`
- `04-logout.png`

## 已知剩余

- 管理端题库、试卷、用户、消息、日志等完整业务模块尚未迁移。
- UEditor/题库富文本闭环尚未迁移，这是下一阶段高风险重点。
- ECharts、xlsx、CodeMirror、screenfull、SVG sprite 等第三方能力尚未完成完整适配。
- 管理端生产入口在阶段 6 时仍未切换到 Vue 3，默认生产管理端仍是旧 Vue 2 工程。

最终状态更新：后续阶段已完成管理端题库、试卷、用户、消息、日志、个人资料等业务模块迁移，默认生产入口已切换到 `frontend/apps/admin`，旧 Vue 2 管理端源码目录已删除。

## 阶段 6 结论

管理端 Vue 3 + Vite 基础壳已经具备可运行基础：可登录、可恢复当前用户、可进入管理布局、可查看 Dashboard、可打开低风险学科列表并退出。下一阶段应进入管理端题库与富文本闭环迁移，优先处理历史 HTML、公式、历史图片外链展示和学生端展示回归。
