# 前端覆盖式重构阶段 5 学生端覆盖切换报告

## 阶段范围

阶段 5 将学生端默认生产构建和后端 `/student` 静态入口切换到 Vue 3 + Vite 版本。

- 日期：2026-07-04
- 应用：`frontend/apps/student`
- 发布入口：`source/xzs/src/main/resources/static/student`

## 已落地内容

默认构建入口：

- `scripts/build-student.ps1` 改为在 `frontend` 工作区执行 `pnpm --filter @xzs/student run build`。
- `scripts/build-all.ps1` 和 `scripts/measure-build.ps1` 通过 `scripts/build-student.ps1` 间接使用 Vue 3 学生端构建。

静态资源同步：

- `scripts/sync-web-static.ps1` 的学生端来源改为 `frontend/apps/student/student`。
- `source/xzs/src/main/resources/static/student` 已同步为 Vue 3 + Vite 产物。

后端集成：

- `scripts/package-backend.ps1` 重新打包后，`source/xzs/target/xzs-3.9.0.jar` 内置 `/student/index.html` 已是 Vite 产物。
- `source/xzs/src/main/resources/application.yml` 补齐压缩 mime types：`text/html`、`text/css`、`application/javascript`、`application/json`、`image/svg+xml`。

验证脚本：

- `frontend/scripts/verify-student-ui-screenshots.mjs` 支持 `XZS_STUDENT_API_BASE_URL`，可分别指定页面入口和 API 服务。
- 截图脚本的 hash URL 构造同时支持目录入口和 `index.html` 入口。
- 个人中心截图断言增加“更换头像”和“保存资料”。

## 验证结果

阶段 5 构建：

```powershell
.\scripts\build-student.ps1 -SkipInstall
```

结果：通过，Vite reported `built in 4.24s`。

静态资源同步：

```powershell
.\scripts\sync-web-static.ps1 -SkipAdmin
```

结果：通过，已同步 `frontend/apps/student/student -> source/xzs/src/main/resources/static/student`。

后端打包：

```powershell
.\scripts\package-backend.ps1
```

第一次在旧后端进程运行时失败，原因是 `target/xzs-3.9.0.jar` 被 Java 进程锁定，Spring Boot repackage 无法重命名 jar。停止后端后重跑通过。

后端启动：

```powershell
.\start.ps1
```

结果：通过，后端使用 PostgreSQL 容器映射端口 `15432` 启动。

后端内置 static 检查：

- `http://localhost:8000/student/index.html` 包含 Vite `type="module"` 脚本。
- `http://localhost:8000/student/index.html` 不再包含旧 Vue CLI `chunk-vendors`。
- `http://localhost:8000/student/static/index-CApbd-5n.js` 在 `Accept-Encoding: gzip` 下返回 `Content-Encoding: gzip`。
- `http://localhost:8000/student/static/index-Vx84fdX9.css` 在 `Accept-Encoding: gzip` 下返回 `Content-Encoding: gzip`。
- `index.html` 未压缩是预期结果，因为当前体积 `1.36 kB` 小于 `min-response-size: 2KB`。

后端 `/student/index.html` 严格截图验证：

```powershell
.\frontend\scripts\verify-student-submit-edit-strict.ps1 -UseTemporarySubjectivePaper -RunScreenshotStrict -FrontendBaseUrl "http://localhost:8000/student/index.html"
```

结果：通过，临时试卷 `paperId=21`、临时答卷 `answerId=20` 已自动清理。

## 已知剩余

- `source/vue/xzs-student` 仍保留旧 Vue 2 源码目录。它已不再是默认生产构建入口，但阶段 10 仍需要删除或替换该目录，避免后续误用。
- 管理端仍未迁移，继续使用 `source/vue/xzs-admin` 的 Vue 2 + Vue CLI 构建。
- 题目渲染共享 chunk 仍偏大，后续阶段可继续拆分 KaTeX、Markdown、DOMPurify 和代码高亮依赖。

## 阶段 5 结论

学生端默认生产构建、后端 static 同步、后端 jar 内置 `/student` 入口和严格真实业务截图验证均已切换到 Vue 3 + Vite。阶段 5 的生产入口切换完成；后续应进入阶段 6 管理端骨架迁移，并在旧工程清理阶段删除 `source/vue/xzs-student`。
