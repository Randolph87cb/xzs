# 阶段 9：Vue 3 覆盖迁移最终清理报告

## 目标

完成覆盖式迁移收口：管理端和学生端 Web 源码只保留 Vue 3 + Vite 实现，删除旧 Vue 2 + Vue CLI 工程，更新脚本、结构文档和验证入口，避免重新形成新旧并行生产入口。

## 改动范围

- 管理端剩余业务模块迁移到 `frontend/apps/admin`：用户、学科、题库、试卷、任务、智能训练、答卷、消息、日志和个人资料。
- 管理端 API 封装补齐到 `frontend/packages/api-client/src/adminOperations.ts`。
- 管理端截图验证扩展到主要菜单路由、表格、表单、UEditor 加载、题目保存回读和临时数据清理。
- 默认构建、同步和后端 static 入口继续使用 `scripts/build-admin.ps1`、`scripts/build-student.ps1`、`scripts/sync-web-static.ps1` 和 `scripts/build-all.ps1`。
- 删除旧 Vue 2 Web 工程目录 `source/vue/xzs-admin` 和 `source/vue/xzs-student`。
- 删除已废弃的 Vue 2.7 + Vite spike 文档和测量脚本。
- 更新项目结构文档、发布说明和 Markdown 渲染测试包装器。

## Harness 分工

- 主线程：完成最终代码整合、旧目录删除、文档更新、构建打包、浏览器截图验证和 Git 提交。
- subagent：只读审查旧路径残留、脚本依赖和验证缺口，不修改文件、不提交 Git。
- 验证脚本：负责类型检查、生产构建、后端 static 同步、后端打包和真实浏览器截图验证。

## 验收标准

- `source/vue/xzs-admin` 和 `source/vue/xzs-student` 不再存在。
- `scripts/test-markdown-renderer.js` 不再依赖旧 Vue2 renderer。
- `scripts/build-admin.ps1`、`scripts/build-student.ps1` 和 `scripts/sync-web-static.ps1` 只使用 `frontend/apps/*` 产物。
- 后端 jar 内 `/admin` 和 `/student` static 来自 Vue 3 + Vite 构建产物。
- 管理端截图验证覆盖主要模块，并验证题目 Markdown、KaTeX 公式、代码高亮和 UEditor 保存回读。

## 后续优化

- 管理端 Vite 构建仍可继续做 chunk 拆分，优先拆 UEditor、Element Plus 自动导入和题目渲染相关依赖。
- 学生端大试卷加载可继续做分批渲染、渲染缓存和题目导航定位优化。
- 发布文档站 `docs/guide/*.html` 是历史静态站产物，仍可能包含上游旧版部署说明；后续如要对外发布，应从文档源重新生成或单独改造。
