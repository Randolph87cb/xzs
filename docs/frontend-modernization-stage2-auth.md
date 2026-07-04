# 前端覆盖式重构阶段 2 登录链路报告

## 阶段范围

阶段 2 的目标是跑通 Vue 3 学生端登录、退出、当前用户恢复、接口错误处理和基础路由鉴权。阶段 2 不迁移试卷业务页面。

- 日期：2026-07-04
- 基于提交：`383850d1`
- 工作区：`frontend/`
- 应用：`frontend/apps/student`

## 已落地内容

新增 `@xzs/api-client` 包：

```text
frontend/packages/api-client/
  package.json
  src/
    auth.ts
    index.ts
    request.ts
    studentUser.ts
```

实现内容：

- axios 请求封装。
- 保留 `withCredentials: true`。
- 保留 `request-ajax: true`。
- 按后端业务 `code` 处理响应。
- `401/502` 统一触发未登录回调。
- `500/501` 统一触发错误提示。
- 登录接口：`POST /api/user/login`。
- 登出接口：`POST /api/user/logout`。
- 当前用户接口：`POST /api/student/user/current`。

学生端实现内容：

- 登录页调用真实后端接口。
- Pinia 用户 store 兼容旧 cookie：`studentUserName`、`studentUserInfo`、`studentImagePath`。
- 首次访问受保护页面时调用 `/api/student/user/current` 校验服务端 session。
- 未登录访问受保护页面跳转 `/login?redirect=...`。
- 登录后跳回 redirect 或 `/index`。
- Shell layout 增加退出入口。

新增验证脚本：

```powershell
.\frontend\scripts\verify-student-auth.ps1
```

该脚本依赖后端 `http://localhost:8000` 已启动，且 Vite dev server `http://localhost:8001` 已启动，用 Vite proxy 验证真实登录链路。

## 旧链路确认

旧学生端登录链路关键点：

- 登录不是 controller，而是 Spring Security filter 拦截 `/api/user/login`。
- 请求体字段必须是 `userName`、`password`、`remember`。
- 登录成功只可靠返回 `response.userName` 和 `response.imagePath`。
- 完整用户信息需要登录后再调用 `/api/student/user/current`。
- 旧学生端没有前端路由鉴权，只在 API 返回 `401/502` 时跳登录。

阶段 2 在此基础上增加了首次 session 校验，这属于行为增强，用于满足刷新后恢复用户态和未登录路由跳转。

## 验证结果

构建命令：

```powershell
.\frontend\scripts\build-student.ps1
```

结果：通过。

构建输出：

| 文件 | 体积 |
| --- | ---: |
| `student/index.html` | `1.06 kB`, gzip `0.61 kB` |
| CSS | `359.64 kB`, gzip `48.51 kB` |
| JS | `1043.10 kB`, gzip `340.61 kB` |

开发服务：

```powershell
pnpm --filter @xzs/student dev -- --open false
```

结果：

- Vite ready in `859 ms`。
- `http://localhost:8001/` 返回 200。

认证接口验证：

```powershell
.\frontend\scripts\verify-student-auth.ps1
```

验证步骤：

- 未登录调用 `/api/student/user/current` 返回 `code=401`。
- 使用 `student / 123456` 调用 `/api/user/login` 返回 `code=1`。
- 登录后调用 `/api/student/user/current` 返回 `code=1` 且 `response.userName=student`。
- 调用 `/api/user/logout` 返回 `code=1`。

## 已知问题

- 当前 UI 仍是阶段 1 骨架，没有迁移注册页。
- 仍未引入 ESLint/Prettier。
- Element Plus 仍为整包接入，导致 JS chunk 超过 500 kB。
- Vite/Rolldown 仍会报告 `@vueuse/core` 的 `INVALID_ANNOTATION` 第三方注释告警，不影响构建通过。
- 手写 curl JSON 时 PowerShell 引号容易导致登录 payload 异常，验证脚本已改用 JSON 文件规避。

## 阶段 2 验收结论

阶段 2 登录链路已跑通：

- 真实后端登录接口可用。
- 刷新后可通过服务端 session 恢复用户态。
- 未登录访问受保护页面会跳登录。
- 登出会清理本地 cookie 并让服务端 session 失效。
