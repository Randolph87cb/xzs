# 数据库与部署资产

`sql/xzs-postgresql.sql` 是 PostgreSQL 初始化脚本，包含序列、表结构和初始化数据。`sql/README.md` 只保留数据库下载地址说明。

## Flyway 迁移

后端已引入 Flyway 管理 PostgreSQL schema 迁移：

- `source/xzs/src/main/resources/db/migration/V1__baseline_schema.sql`：当前基线迁移，内容来自 `sql/xzs-postgresql.sql`，用于全新空库初始化。
- `docs/database-migration-flyway.md`：Flyway 配置策略、空库初始化、已有库接入、备份要求、失败处理和后续迁移命名规范。

已有非空数据库接入 Flyway 前必须先备份；后续业务 schema 变更应新增递增版本迁移文件，不再直接改写已发布迁移。

## 发布包

`release` 目录保存已构建产物：

- `release/java/xzs-3.9.0.jar`：后端 jar。
- `release/web/admin`：管理端静态资源。
- `release/web/student`：学生端静态资源。

## Docker 目录

`docker` 目录保存 Docker 部署材料：

- `docker/docker-compose.yml`：compose 配置。
- `docker/.env.production.example`：树莓派生产环境 env 模板，真实 `.env` 必须在树莓派本机维护并连接 Neon `production` branch。
- `docker/README.md`：Docker Compose 启动、日志、JVM/Undertow/Hikari 参数、Cloudflare 缓存检查、ACR 镜像更新和回滚说明。
- `docs/container-image-deployment.md`：树莓派和 Fly 共用 `Dockerfile` 的容器镜像、运行参数、模板入口和验证入口说明。

当前树莓派 Docker Compose 只运行应用容器，镜像来自阿里云 ACR，镜像内已包含后端 Jar、管理端和学生端静态资源。生产数据库在 Neon `production` branch，Compose 不再默认启动本地 PostgreSQL，也不再挂载 `release/java/xzs-3.9.0.jar`。运行 Docker 部署前需要在目标环境外部安装 Docker Compose v2，仓库不再附带 docker-compose 二进制。

## Neon 数据库

当前线上数据库默认使用 Neon PostgreSQL：

- 部署环境固定为：树莓派是生产环境，Fly.io 是测试环境，本地是开发环境。
- 树莓派生产环境使用 Neon `production` branch。
- Fly 测试环境和本地开发环境使用 Neon `test` branch，避免测试写入污染生产数据。
- 后端支持将 Neon 原始连接串直接写入 `SPRING_DATASOURCE_URL`，格式为 `postgresql://<user>:<password>@<branch-host>/<database>?sslmode=require&channel_binding=require`。启动时会自动转换为 JDBC URL，并移除当前 PostgreSQL JDBC 驱动不支持的 `channel_binding` 参数。
- 如果连接串已经包含用户名和密码，不需要额外配置 `SPRING_DATASOURCE_USERNAME` 和 `SPRING_DATASOURCE_PASSWORD`；显式环境变量仍可覆盖连接串中的用户信息。
- 本地真实测试配置写入 `.env.neon-test`，模板见 `.env.neon-test.example`。`.env.neon-test` 和其他 `.env*` 真实环境文件被 Git 忽略，禁止提交完整连接串、密码或 Fly/Neon secrets。
- Neon 免费/低配环境默认使用 `SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE=3`、`SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE=1`，避免连接数占用过高。
- `test` branch 可以在 Neon 控制台从 `production` branch reset 或重建以复制生产数据；该操作会丢弃 `test` branch 当前数据，执行前需要确认测试数据不需要保留。

## Fly.io 部署

根目录 `Dockerfile` 和 `fly.toml` 用于 Fly.io 部署：

- `Dockerfile`：多阶段构建，先构建 Vue 3 + Vite 管理端和学生端，再将产物复制到 Spring Boot static，最后打包运行 jar。
- `fly.toml`：Fly App 配置模板，默认内部端口为 `8000`。
- `docs/fly-managed-postgres-deployment.md`：Fly.io Web App 部署、Neon 数据库 secret 配置，以及历史 Fly Postgres 冷启动方案说明。
- `scripts/deploy-fly-neon-test.ps1`：从被 Git 忽略的 `.env.neon-test` 导入 Neon `test` branch secret，部署 Fly 测试环境，并运行远端健康检查。

当前 Fly Web App 是测试环境，必须连接 Neon `test` branch，不再依赖 Fly Postgres 作为主库，也不连接 Neon `production` branch。Fly 旧 Postgres App `xzs-pg-cb867393296` 已停止，仅作为历史迁移来源或回滚参考；销毁旧 App 或 Volume 前必须先取得用户明确确认。

## 树莓派部署

`deploy/raspberry-pi` 保存树莓派运行环境专用部署资产：

- `deploy/raspberry-pi/xzs.service`：systemd 服务模板，包含低资源设备适配的 JVM、Undertow、Hikari 参数和生产环境变量占位符。
- `deploy/raspberry-pi/init-db.sh`：在树莓派 PostgreSQL 上创建或更新应用数据库用户、数据库并导入初始化脚本。
- `deploy/raspberry-pi/backup-db.sh`：使用 `pg_dump --format custom` 生成带时间戳的数据库备份，并按保留数量清理旧备份。
- `deploy/raspberry-pi/restore-db.sh`：从指定备份恢复数据库，要求显式确认后执行。
- `docs/raspberry-pi-deployment.md`：树莓派运行目录、部署资产安装、数据库初始化、systemd 启停、备份、恢复和健康检查说明。
- `docs/fly-to-raspberry-pi-data-migration-plan.md`：历史迁移方案，仅作为 Fly Postgres 到树莓派 Docker PostgreSQL 的历史切换参考；当前生产环境使用树莓派 + Neon `production` branch。

树莓派是生产环境。树莓派普通运行时不承担 Maven 或前端构建任务；应在开发机或 CI 构建完成后，只复制后端 jar、SQL 脚本和运行所需部署资产，并确保生产服务连接 Neon `production` branch。

## 集成部署提示

集成部署时，将管理端构建产物 `admin` 和学生端构建产物 `student` 放到 `source/xzs/src/main/resources/static` 后，再打包后端 jar。当前学生端构建产物来自 `frontend/apps/student/student`，管理端构建产物来自 `frontend/apps/admin/admin`。

仓库根目录提供了构建脚本：

- `scripts/sync-web-static.ps1`：同步两个 Web 构建产物到后端静态资源目录；学生端和管理端默认同步 Vue 3 + Vite 产物。
- `scripts/verify-admin-static.ps1`：验证后端 `/admin/index.html` 是否服务 Vue 3 + Vite 管理端，并复用管理端浏览器严格验证。
- `scripts/package-backend.ps1`：使用 Maven Wrapper、系统 Maven 或临时 Maven 打包后端。
- `scripts/build-all.ps1`：按管理端、学生端、静态资源同步、后端打包顺序执行集成构建。
- `scripts/measure-build.ps1`：记录各阶段耗时，便于对比优化效果。

题库解析治理相关脚本：

- `scripts/generate-question-analysis.ps1`：从题源 Markdown 生成解析 API prompt、请求体、manifest 和人工复核队列；默认 prompt-only，不调用外部 API。
- `scripts/sync-question-analysis-to-remote.ps1`：根据解析 manifest 生成远端同步 SQL，强制使用 `import_batch + import_source + import_question_order` 匹配；默认只生成 SQL，不写库。
- `docs/question-bank/analysis-generation-api-prompt.md`：解析生成 API prompt 模板，约束输入字段、输出结构和质量规则。
