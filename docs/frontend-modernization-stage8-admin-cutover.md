# 前端覆盖式重构阶段 8 管理端生产入口切换报告

## 阶段范围

阶段 8 将管理端 Vue 3 + Vite 从迁移工作区接入默认生产构建和后端 `/admin` static 入口。

- 日期：2026-07-04
- 应用：`frontend/apps/admin`
- 构建输出：`frontend/apps/admin/admin`
- 后端入口：`source/xzs/src/main/resources/static/admin`

## 已落地内容

默认管理端构建脚本已切换：

```powershell
.\scripts\build-admin.ps1
```

现在使用：

```powershell
pnpm --filter @xzs/admin run build
```

后端 static 同步脚本已切换：

```powershell
.\scripts\sync-web-static.ps1
```

现在把 `frontend/apps/admin/admin` 同步到 `source/xzs/src/main/resources/static/admin`。

管理端 `favicon.ico` 已补入 `frontend/apps/admin/public/favicon.ico`，并随 Vite 构建同步到后端 `/admin/favicon.ico`。

新增后端 static 验证脚本：

```powershell
.\scripts\verify-admin-static.ps1
```

该脚本会先检查源码 static 是否为 Vite 输出，并确认 `favicon.ico` 存在；再检查运行中的 `/admin/index.html` 和 `/admin/favicon.ico` 是否可访问；最后复用 `pnpm verify:admin-ui` 做真实浏览器验证。

管理端 UEditor 包装层关闭了不参与当前题目编辑的 `message` 自定义 UI 插件，并显式禁用底部路径、字数和缩放 UI，避免 UEditor 在 Vue 路由挂载时因异步 `ready` 回调访问未初始化的 `editor.ui.getDom`。

## 验证结果

管理端构建：

```powershell
.\scripts\build-admin.ps1 -SkipInstall
```

结果：通过。最终复核构建 Vite reported `built in 3.08s`。

后端 static 同步：

```powershell
.\scripts\sync-web-static.ps1 -SkipStudent
```

结果：通过。

后端打包：

```powershell
.\scripts\package-backend.ps1
```

结果：通过，生成 `source/xzs/target/xzs-3.9.0.jar`，Maven resources 复制 `803` 个资源。

后端 `/admin` static 严格验证：

```powershell
.\scripts\verify-admin-static.ps1
```

结果：通过。脚本确认：

- `source/xzs/src/main/resources/static/admin/index.html` 是 Vite 输出。
- `source/xzs/src/main/resources/static/admin/static` 中存在 JS/CSS 资源。
- `http://localhost:8000/admin/index.html` 实际服务的是 Vite 输出。
- `http://localhost:8000/admin/favicon.ico` 可访问。
- 管理端登录、Dashboard、学科列表、题目列表、题目预览、UEditor 加载、题目保存回读和退出通过 Playwright 验证。

Subagent 独立只读复核发现两个必须修正项：`favicon.ico` 缺失、`docs/project-structure/reading-guide.md` 仍指向旧 Vue2 管理端入口。两项均已修正，并纳入最终验证。

## 注意事项

运行中的后端 jar 不会自动读取 `src/main/resources/static/admin` 的最新内容。同步 static 后必须重新打包并重启后端，`verify-admin-static.ps1` 会在浏览器验证前检查 HTTP 返回内容是否已经是 Vite 输出。

旧管理端源码目录 `source/vue/xzs-admin` 尚未删除。当前 Vue 3 管理端已接管默认构建和 `/admin` static，但业务模块覆盖仍不完整，旧目录暂时保留作历史对照和后续模块迁移参考。

## 阶段 8 结论

管理端默认生产构建和后端 `/admin` static 入口已切换到 Vue 3 + Vite。后续阶段应继续迁移管理端剩余业务模块，并在完整验收后删除旧 Vue 2 管理端源码、Vue CLI 配置和相关遗留脚本。
