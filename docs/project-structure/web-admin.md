# 管理端 Vue 项目结构

管理端默认生产构建当前位于 `frontend/apps/admin`，构建输出目录为 `admin`，开发端口为 `8002`，开发代理将 `/api` 转发到 `http://localhost:8000`。后端 `/admin` static 入口由 `frontend/apps/admin/admin` 同步到 `source/xzs/src/main/resources/static/admin` 后打包提供。

`source/vue/xzs-admin` 是旧 Vue 2 管理端历史目录，暂时保留作剩余模块迁移参考，不再是默认生产构建入口。

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
    ├── views/        # 登录、Dashboard、学科、题库等页面
    ├── main.ts
    ├── App.vue
    └── ...
```

## 主要页面模块

- `views/dashboard`：后台首页统计。
- `views/education/SubjectListView.vue`：学科列表。
- `views/question/QuestionListView.vue`：题目列表和预览。
- `views/question/QuestionEditView.vue`：题目编辑和 UEditor 富文本闭环。
- 旧 Vue 2 管理端仍包含用户、试卷、任务、答卷、消息、日志、个人资料等历史模块，这些模块尚待迁移到 Vue 3 管理端。

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

严格截图验证会创建并清理临时题：

```powershell
pnpm --dir frontend verify:admin-ui
```

后端 `/admin` static 入口验证：

```powershell
.\scripts\verify-admin-static.ps1
```
