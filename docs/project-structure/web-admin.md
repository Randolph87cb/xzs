# 管理端 Vue 项目结构

管理端 Web 源码和默认生产构建位于 `frontend/apps/admin`，技术栈为 Vue 3 + Vite + TypeScript + Pinia + Element Plus。构建输出目录为 `frontend/apps/admin/admin`，开发端口为 `8002`，开发代理将 `/api` 转发到 `http://localhost:8000`。后端 `/admin` static 入口由 `frontend/apps/admin/admin` 同步到 `source/xzs/src/main/resources/static/admin` 后打包提供。

旧 Vue 2 管理端工程已删除，不再保留并行源码入口。

```text
frontend/apps/admin/
├── package.json
├── vite.config.ts
├── index.html
├── public/
└── src/
    ├── components/   # UEditor wrapper 等通用组件
    ├── layouts/      # 后台布局、侧边栏、导航
    ├── router/       # Vue Router 4 路由和静态菜单
    ├── stores/       # Pinia 状态
    ├── styles/       # 全局样式
    ├── views/        # 登录、Dashboard 和管理端业务页面
    ├── main.ts
    ├── App.vue
    └── ...
```

## 主要页面模块

- `views/dashboard`：后台首页统计。
- `views/user`：学生和管理员列表、编辑、状态切换和删除。
- `views/education`：学科列表、新增、编辑和删除。
- `views/question/QuestionListView.vue`：题目列表、预览和删除。
- `views/question/QuestionEditView.vue`：题目编辑和 UEditor 富文本闭环。
- `views/paper`：试卷列表、创建和编辑。
- `views/task`：任务列表、创建和编辑。
- `views/smartTraining`：智能训练配置。
- `views/answer`：答卷列表。
- `views/message`：消息列表和发送。
- `views/log`：用户日志。
- `views/profile`：个人资料。

## 常用命令

```powershell
pnpm --dir frontend --filter @xzs/admin dev
```

```powershell
pnpm --dir frontend --filter @xzs/admin build
```

或从仓库根目录运行默认生产构建：

```powershell
.\scripts\build-admin.ps1 -SkipInstall
```

严格截图验证会创建并清理临时题，并覆盖主要管理端路由：

```powershell
pnpm --dir frontend verify:admin-ui
```

后端 `/admin` static 入口验证：

```powershell
.\scripts\verify-admin-static.ps1
```
