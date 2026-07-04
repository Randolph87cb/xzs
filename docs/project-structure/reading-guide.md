# 代码阅读入口建议

如果要理解一次完整业务链路，可以按以下顺序阅读：

1. Web 路由：管理端读 `frontend/apps/admin/src/router/index.ts`，学生 Web 端读 `frontend/apps/student/src/router/index.ts`。
2. 页面组件：对应 `views` 目录下的 `.vue` 文件。
3. 前端 API：管理端和学生 Web 端都读 `frontend/packages/api-client/src/*.ts`。
4. 后端 Controller：对应 `source/xzs/src/main/java/com/mindskip/xzs/controller`。
5. Service 实现：对应 `source/xzs/src/main/java/com/mindskip/xzs/service/impl`。
6. Mapper 与 SQL：`source/xzs/src/main/java/com/mindskip/xzs/repository` 和 `source/xzs/src/main/resources/mapper`。
7. 实体与 VM：`domain` 和 `viewmodel`。

## 按端阅读

- 管理端：先读 `frontend/apps/admin/src/router/index.ts`，再进入对应 `views`、`components` 和 `frontend/packages/api-client/src/*.ts`，最后查 `/api/admin/...` 的后端 Controller。
- 学生 Web 端：先读 `frontend/apps/student/src/router/index.ts`，再进入对应 `views`、`components` 和 `frontend/packages/api-client/src/*.ts`，最后查 `/api/student/...` 的后端 Controller。
- 微信小程序：先读 `source/wx/xzs-student/app.json` 和 `app.js`，再按 `pages` 目录查页面，最后查 `/api/wx/student/...` 的后端 Controller。
