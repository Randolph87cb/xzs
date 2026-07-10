# 项目结构概览

信息学客观题一本通是一套面向 GESP/CSP 客观题训练的 Java + Vue 前后端分离练习系统，基于开源考试系统 PostgreSQL 版改造，并附带微信小程序学生端。仓库同时包含源码、静态文档站、数据库脚本、Docker 配置、设备部署资产和已构建发布包。

主要技术栈：

- 后端：Java 8、Spring Boot 2.7.18、Spring Security、MyBatis、PageHelper、Undertow、PostgreSQL、Flyway。
- Web 前端：学生端和管理端源码均位于 `frontend/` 工作区，技术栈为 Vue 3、Vue Router 4、Pinia、Element Plus、Vite；旧 Vue 2 Web 目录已删除。
- 微信小程序：原生微信小程序，内置 iView Weapp 组件。
- 数据库：PostgreSQL 初始化脚本位于 `sql/xzs-postgresql.sql`，Flyway 迁移脚本位于 `source/xzs/src/main/resources/db/migration/`。

## 顶层目录

```text
xzs/
├── deploy/              # 设备和环境专用部署资产
│   └── raspberry-pi/    # 树莓派 systemd 服务模板、数据库初始化、备份和恢复脚本
├── docker/              # Docker 部署材料，包含 compose、安装文件和发布 jar
├── docs/                # 已构建的项目文档站静态文件、结构拆分文档和题库资料
│   ├── project-structure/ # 项目结构拆分文档
│   └── question-bank/   # 随项目版本管理的真题题库 Markdown 资料
├── release/             # 已构建发布包：后端 jar 与前端静态包
├── frontend/            # Vue 3 + Vite Web 前端工作区
├── scripts/             # 本地构建、测量、静态资源同步、维护和数据导入脚本
├── source/              # 源码根目录
│   ├── xzs/             # Spring Boot 后端
│   └── wx/              # 微信小程序源码
│       └── xzs-student/ # 学生端小程序
├── sql/                 # PostgreSQL 建库/建表/初始化脚本
├── AGENTS.md            # 面向后续协作者的项目结构简述
├── Dockerfile           # Fly.io 远端构建用多阶段镜像
├── fly.toml             # Fly.io 应用配置模板
├── PROJECT_STRUCTURE.md # 项目结构文档索引
├── README.md            # 项目介绍、功能说明与外部文档链接
└── LICENSE              # AGPL-3.0
```

## 拆分文档

- `backend.md`：Spring Boot 后端结构。
- `web-admin.md`：管理端 Vue 项目结构。
- `web-student.md`：学生端 Vue 项目结构。
- `frontend-modernization.md`：Vue 3 + Vite 覆盖式重构工作区结构。
- `wx-student.md`：微信小程序学生端结构。
- `database-deploy.md`：数据库、发布包与部署资产。
- `reading-guide.md`：按业务链路阅读代码的建议入口。

## 构建优化文档

- `docs/project-health-improvement-plan.md`：项目工程健康改进计划与分阶段执行建议。
- `docs/build-performance-optimization-plan.md`：构建与运行性能优化分阶段方案。
- `docs/vue3-vite-migration-roadmap.md`：Vue 3 + Vite 长期迁移路线图。
- `docs/frontend-modernization-migration-roadmap.md`：覆盖式 Vue 3 + Vite 前端重构路线。
- `docs/frontend-modernization-stage1-student-shell.md`：学生端现代前端骨架阶段验收报告。
- `docs/frontend-modernization-stage2-auth.md`：学生端认证链路阶段验收报告。
- `docs/frontend-modernization-stage3-question-renderer.md`：题目渲染包阶段验收报告。
- `docs/frontend-modernization-stage4-student-core-loop.md`：学生端核心业务阶段验收报告。
- `docs/frontend-modernization-stage5-student-cutover.md`：学生端生产入口覆盖切换报告。
- `docs/frontend-modernization-stage6-admin-shell.md`：管理端 Vue 3 + Vite 基础壳阶段验收报告。
- `docs/frontend-modernization-stage7-admin-question-ueditor.md`：管理端题库与 UEditor 闭环阶段验收报告。
- `docs/frontend-modernization-stage8-admin-cutover.md`：管理端生产入口覆盖切换报告。
- `docs/frontend-modernization-stage9-final-cutover-cleanup.md`：Vue 3 覆盖迁移最终清理报告。
- `docs/database-migration-flyway.md`：Flyway 数据库迁移、基线和后续迁移规范说明。
- `docs/fly-managed-postgres-deployment.md`：Fly.io 冷启动按量部署说明。
- `docs/raspberry-pi-deployment.md`：树莓派运行目录、systemd 服务、数据库初始化、备份和恢复说明。
