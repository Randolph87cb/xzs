# 项目协作说明

## 项目结构概览

本项目是学之思开源考试系统 PostgreSQL 版，包含一个 Spring Boot 后端、两个 Vue 2 Web 前端、一个微信小程序学生端，以及迁移中的 Vue 3 + Vite 覆盖式重构工作区。

- 后端源码在 `source/xzs`，主要按 `controller`、`service`、`repository`、`domain`、`viewmodel` 分层。
- 管理端 Web 在 `source/vue/xzs-admin`，学生端 Web 在 `source/vue/xzs-student`。
- 现代前端迁移工作区在 `frontend`，当前用于 Vue 3 + Vite 覆盖式重构；它不是长期新旧并行入口。
- 微信小程序学生端在 `source/wx/xzs-student`。
- PostgreSQL 初始化脚本在 `sql/xzs-postgresql.sql`。
- 真题题库 Markdown 资料在 `docs/question-bank`。
- 本地构建、测量、静态资源同步、维护和数据导入脚本在 `scripts`。
- 构建性能优化方案和迁移评估文档在 `docs/build-performance-optimization-plan.md`、`docs/vite-vue2-migration-spike.md`、`docs/vue3-vite-migration-roadmap.md`、`docs/frontend-modernization-migration-roadmap.md`。
- 发布包与部署材料分别在 `release` 和 `docker`。

## 项目结构文档

详细项目结构文档已拆分到 `docs/project-structure/`：

- `README.md`：项目概览与顶层目录。
- `backend.md`：后端结构。
- `web-admin.md`：管理端 Web 结构。
- `web-student.md`：学生端 Web 结构。
- `frontend-modernization.md`：Vue 3 + Vite 覆盖式重构工作区结构。
- `wx-student.md`：微信小程序结构。
- `database-deploy.md`：数据库与部署资产。
- `reading-guide.md`：代码阅读入口建议。

根目录 `PROJECT_STRUCTURE.md` 也保留了上述结构文档索引。

## 维护规则

- 如果项目目录结构发生新增、删除、移动或职责变化，需要同步更新 `docs/project-structure/` 下的相关结构文档；如果结构文档清单变化，也要同步更新根目录 `PROJECT_STRUCTURE.md` 和本文件中的文档位置说明。
