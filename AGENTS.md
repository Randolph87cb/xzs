# 项目协作说明

## 项目结构概览

本项目是学之思开源考试系统 PostgreSQL 版，包含一个 Spring Boot 后端、两个 Vue 2 Web 前端和一个微信小程序学生端。

- 后端源码在 `source/xzs`，主要按 `controller`、`service`、`repository`、`domain`、`viewmodel` 分层。
- 管理端 Web 在 `source/vue/xzs-admin`，学生端 Web 在 `source/vue/xzs-student`。
- 微信小程序学生端在 `source/wx/xzs-student`。
- PostgreSQL 初始化脚本在 `sql/xzs-postgresql.sql`。
- 发布包与部署材料分别在 `release` 和 `docker`。

## 项目结构文档

详细项目结构文档已拆分到 `docs/project-structure/`：

- `README.md`：项目概览与顶层目录。
- `backend.md`：后端结构。
- `web-admin.md`：管理端 Web 结构。
- `web-student.md`：学生端 Web 结构。
- `wx-student.md`：微信小程序结构。
- `database-deploy.md`：数据库与部署资产。
- `reading-guide.md`：代码阅读入口建议。

根目录 `PROJECT_STRUCTURE.md` 也保留了上述结构文档索引。
