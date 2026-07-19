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
- 树莓派部署说明在 `docs/raspberry-pi-deployment.md` 和 `docker/README.md`；树莓派与 Fly 共用容器镜像的说明在 `docs/container-image-deployment.md`；对应 systemd 服务模板和数据库初始化、备份、恢复脚本在 `deploy/raspberry-pi`。
- 发布包与部署材料分别在 `release`、`docker` 和 `deploy`。

## 树莓派与 Docker 运维入口

- 树莓派迁移、性能、备份、恢复或故障排查任务开始前，先确认当前实际部署方式是 Docker Compose、systemd/Jar 还是其他方式。
- 用户已说明树莓派使用 Docker 时，优先读取 `docs/container-image-deployment.md`、`docker/README.md` 和 `docker/docker-compose.yml`；历史迁移问题再结合 `docs/fly-to-raspberry-pi-data-migration-plan.md`。
- 未确认部署方式时，不要直接套用 `deploy/raspberry-pi` 的 systemd/Jar 流程；`docs/raspberry-pi-deployment.md` 只代表 systemd/Jar 直部署路线。

## Neon 数据库配置约定

- 当前在线数据库默认使用 Neon PostgreSQL；部署环境固定为：树莓派是生产环境，Fly.io 是测试环境，本地是开发环境。
- 树莓派生产环境必须连接 Neon `production` branch；Fly 测试环境和本地开发环境必须连接 Neon `test` branch。除非用户明确要求只读排查，不要让测试或本地服务连接 `production` branch。
- Fly Web App 部署必须使用 `scripts/deploy-fly-neon-test.ps1` 从 `.env.neon-test` 导入 secret 并部署；不要手工把 `.env.neon-test` 内容打印到日志、聊天或可提交文件。
- Neon 连接优先使用原始 URL 形式写入 `SPRING_DATASOURCE_URL`，例如 `postgresql://<user>:<password>@<branch-host>/<database>?sslmode=require&channel_binding=require`。后端启动入口会自动转换为 Spring JDBC URL，并移除当前 JDBC 驱动不支持的 `channel_binding` 参数。
- 本地真实配置写入 `.env.neon-test`，该文件被 Git 忽略；可提交模板为 `.env.neon-test.example`。不要把 Neon 密码、完整连接串或 Fly/Neon secrets 写入可提交文档、脚本或日志。
- 本地 Neon test branch 启动后端优先使用 `scripts/start-local-neon.ps1`，由脚本统一完成前端构建、静态资源同步、启动前文件级一致性校验、`spring-boot:run` 受控启动和启动后 HTTP 一致性校验；正常启动前如果 BaseUrl 已有 `/admin/index.html` 或 `/student/index.html` 可访问，脚本默认失败，需先停止旧服务，或显式传 `-UseExistingService` 只校验已有服务并退出。
- `scripts/start-local-neon.ps1` 会在 `.env.neon-test` 缺少 `XZS_AI_CONFIG_SECRET` 时自动生成本地随机值，用于加密老师保存的 AI 预审 API Key；不要把真实值写入可提交文件。已用其它方式启动的后端不会自动读取新值，需要重启。
- 修改管理端或学生端 Web 前端后，验收必须运行 `scripts/verify-web-static-consistency.ps1`，或通过 `scripts/start-local-neon.ps1` / `scripts/build-all.ps1` 的内置校验通过；`verify-web-static-consistency.ps1` 会合并设置 localhost NO_PROXY，默认要求 `source/xzs/target/classes/static` 存在并一致，只有确认后端本地直读 Vite 输出时才允许显式传 `-AllowMissingRuntimeStatic`；需要确认运行中服务时不要传 `-SkipHttpCheck`。
- Hikari 在 Neon 免费/低配环境默认使用保守配置：`SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE=3`、`SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE=1`。提高并发前先检查 Neon 连接数、冷启动和查询耗时。
- Neon branch 管理约定：`test` branch 可从 `production` branch reset 或重建以复制生产数据；reset 会丢弃 `test` branch 上的测试写入，执行前先确认没有需要保留的数据。
- Fly 旧 Postgres App `xzs-pg-cb867393296` 已停止，只作为历史迁移来源或回滚参考；销毁 App 或 Volume 是不可逆删除，必须用户明确确认后才能执行。

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
