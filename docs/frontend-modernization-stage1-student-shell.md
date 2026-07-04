# 前端覆盖式重构阶段 1 学生端骨架报告

## 阶段范围

阶段 1 的目标是建立现代前端工作区和学生端 Vue 3 + Vite 基础壳，只验证工程结构、开发服务、构建链路和基础路由，不迁移复杂业务。

- 日期：2026-07-04
- 基线 tag：`vue2-baseline-20260704`
- 当前阶段：学生端骨架
- 工作区：`frontend/`

## 已落地内容

新增 pnpm workspace：

```text
frontend/
  package.json
  pnpm-workspace.yaml
  tsconfig.base.json
  apps/
    student/
  packages/
    config/
    shared/
```

学生端骨架：

- Vue 3 + Vite + TypeScript。
- Vue Router 4 hash history，保留旧学生端 hash 路由习惯。
- Pinia 用户状态基础壳。
- Element Plus 基础接入。
- NProgress 路由进度条。
- `base: './'`、`assetsDir: 'static'`、`outDir: 'student'`。
- 开发代理 `/api -> http://localhost:8000`。
- `@` alias 指向 `apps/student/src`。
- 登录页壳、首页壳、基础布局和 404 路由。
- 复用旧学生端 `favicon.ico`。

辅助脚本：

- `frontend/scripts/dev-student.ps1`
- `frontend/scripts/build-student.ps1`

## 依赖版本

当前锁定版本：

| 依赖 | 版本 |
| --- | --- |
| `pnpm` | `11.9.0` |
| `vite` | `8.1.3` |
| `@vitejs/plugin-vue` | `6.0.7` |
| `vue` | `3.5.39` |
| `vue-router` | `4.6.4` |
| `pinia` | `3.0.4` |
| `element-plus` | `2.14.2` |
| `typescript` | `6.0.3` |
| `vue-tsc` | `3.1.8` |
| `sass` | `1.101.0` |

依赖安装中遇到 `@parcel/watcher` build script 被 pnpm 阻止的问题，已在 `pnpm-workspace.yaml` 中加入：

```yaml
onlyBuiltDependencies:
  - '@parcel/watcher'
```

## 验证结果

依赖安装：

```powershell
pnpm install
```

结果：通过。

构建命令：

```powershell
pnpm --filter @xzs/student build
```

结果：通过。

构建耗时：

| 指标 | 结果 |
| --- | ---: |
| 首次 Vite build | `4.41s` |
| 脚本复测 Vite build | `1.20s` |
| `index.html` | `1.06 kB`, gzip `0.61 kB` |
| CSS | `359.59 kB`, gzip `48.50 kB` |
| JS | `1002.59 kB`, gzip `325.23 kB` |

开发服务：

```powershell
pnpm --filter @xzs/student dev -- --open false
```

结果：

- Vite ready in `822 ms`。
- `http://localhost:8001/` 在禁用系统代理后返回 200。
- PowerShell `Invoke-WebRequest` 需要使用 `-NoProxy`，否则本机代理环境会返回 502。

示例：

```powershell
Invoke-WebRequest -UseBasicParsing -NoProxy http://localhost:8001/
```

## 已知问题

阶段 1 只完成骨架，以下内容尚未完成：

- 还没有接入真实登录 API。
- 还没有路由鉴权。
- 还没有迁移学生端业务页面。
- 还没有接入 `question-renderer`。
- 还没有 ESLint 和 Prettier 配置。
- Element Plus 目前整包接入，骨架 JS 仍偏大，后续应改为按需导入。

构建告警：

- `@vueuse/core` 依赖中存在 Rolldown `INVALID_ANNOTATION` 告警，来自第三方包注释格式，不影响当前构建产物。
- 单个 JS chunk 超过 Vite 默认 500 kB 提示，原因是阶段 1 整包引入 Element Plus。阶段 4 前应拆分路由和渲染包，阶段 5 前应按需导入组件。

## 阶段 1 验收结论

阶段 1 的核心骨架已可用：

- 新 workspace 可安装依赖。
- 学生端 Vite dev server 可启动。
- 学生端 Vite build 可通过。
- 输出路径和静态资源路径保持与旧学生端发布入口兼容。

进入阶段 2 前需要补齐 ESLint/Prettier，或明确把代码风格工具延后到学生端核心业务迁移前统一接入。
