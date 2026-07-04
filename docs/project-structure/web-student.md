# 学生端 Web 项目结构

学生 Web 端默认构建来源已经切换到 `frontend/apps/student`，技术栈为 Vue 3 + Vite + TypeScript + Pinia + Element Plus。构建输出目录为 `frontend/apps/student/student`，开发端口为 `8001`，开发代理将 `/api` 转发到 `http://localhost:8000`。

`source/vue/xzs-student` 仍保留旧 Vue 2 + Vue CLI 源码作为迁移期历史目录，但不再是默认生产构建入口；后续旧工程清理阶段应删除或替换该目录，避免重新形成新旧并行生产入口。

```text
frontend/apps/student/
├── package.json
├── vite.config.ts
├── index.html
└── src/
    ├── components/   # 题目答题、题目查看等业务组件
    ├── layouts/      # 学生端整体布局
    ├── router/       # Vue Router 4 路由和守卫
    ├── stores/       # Pinia 状态
    ├── styles/       # 全局样式
    ├── utils/        # 格式化等工具函数
    ├── views/        # 页面
    ├── main.ts
    ├── App.vue
    └── env.d.ts
```

## 主要页面模块

- `views/dashboard`：学生首页与任务入口。
- `views/paper`：试卷中心。
- `views/exam`：答题、查看试卷和批改待批改试卷。
- `views/record`：考试记录。
- `views/question`：错题本。
- `views/training`：智能训练入口。
- `views/user`：个人中心、资料编辑、头像上传和消息中心。
- `views/login`：登录。

题目 Markdown、历史 HTML、KaTeX 公式和代码高亮渲染由 `frontend/packages/question-renderer` 提供；学生端接口封装由 `frontend/packages/api-client` 提供。

## 常用命令

从仓库根目录运行：

```powershell
.\frontend\scripts\dev-student.ps1
```

```powershell
.\frontend\scripts\build-student.ps1
```

生产构建默认入口：

```powershell
.\scripts\build-student.ps1 -SkipInstall
```

生产静态资源同步到后端：

```powershell
.\scripts\sync-web-static.ps1 -SkipAdmin
```
