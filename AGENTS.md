# 项目协作说明

## 项目结构概览

本项目是“信息学客观题一本通 / GESP/CSP 客观题训练”，基于开源考试系统 PostgreSQL 版改造，包含一个 Spring Boot 后端、一个 Vue 3 + Vite 管理端、一个 Vue 3 + Vite 学生端，以及一个微信小程序学生端。

- 后端源码在 `source/xzs`，主要按 `controller`、`service`、`repository`、`domain`、`viewmodel` 分层。
- 管理端 Web 源码和默认构建来源在 `frontend/apps/admin`。
- 学生端 Web 源码和默认构建来源在 `frontend/apps/student`。
- 现代前端工作区在 `frontend`，承载 Vue 3 + Vite 学生端、管理端和共享包；旧 Vue 2 Web 目录已删除，不再保留新旧并行入口。
- 微信小程序学生端在 `source/wx/xzs-student`。
- PostgreSQL 初始化脚本在 `sql/xzs-postgresql.sql`；后端 Flyway 迁移脚本在 `source/xzs/src/main/resources/db/migration`。
- 真题题库 Markdown 资料在 `docs/question-bank`。
- 本地构建、测量、静态资源同步、维护和数据导入脚本在 `scripts`。
- 构建性能优化方案和已完成的现代前端迁移路线在 `docs/build-performance-optimization-plan.md`、`docs/frontend-modernization-migration-roadmap.md`。
- Fly.io 冷启动按量部署说明在 `docs/fly-managed-postgres-deployment.md`；根目录 `Dockerfile` 和 `fly.toml` 是 Fly 部署入口。
- 树莓派部署说明在 `docs/raspberry-pi-deployment.md`；对应 systemd 服务模板和数据库初始化、备份、恢复脚本在 `deploy/raspberry-pi`。
- 发布包与部署材料分别在 `release`、`docker` 和 `deploy`。

## 树莓派与 Docker 运维入口

- 树莓派迁移、性能、备份、恢复或故障排查任务开始前，先确认当前实际部署方式是 Docker Compose、systemd/Jar 还是其他方式。
- 用户已说明树莓派使用 Docker 时，优先读取 `docker/README.md` 和 `docker/docker-compose.yml`，再结合 `docs/fly-to-raspberry-pi-data-migration-plan.md` 判断迁移、备份和冷备流程。
- 未确认部署方式时，不要直接套用 `deploy/raspberry-pi` 的 systemd/Jar 流程；`docs/raspberry-pi-deployment.md` 只代表 systemd/Jar 直部署路线。

## docs 目录使用规则

- `docs/project-structure/`、`docs/question-bank/`、部署说明和可执行运维文档是当前事实来源。
- `docs/guide/`、`docs/assets/` 和 `docs/index.html` 是上游静态文档站构建产物，只作历史参考，不作为当前开发、数据库或部署事实来源。
- 一次性计划、阶段报告和复盘文档完成后默认不要长期留在 `docs` 顶层；确需保留时应明确归档或合并到当前维护文档。
- 学生端和管理端 Web 生产入口已经统一为 Vue 3 + Vite 的 `frontend/apps/student` 和 `frontend/apps/admin`，不再新增或恢复 Vue 2 / Vue CLI 生产入口。

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
