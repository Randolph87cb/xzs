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
- `docker/release/xzs-3.9.0.jar`：Docker 部署使用的 jar。
- `docker/install/docker-compose-linux-x86_64`：附带的 docker-compose 二进制。

注意：当前仓库 README、后端配置和 SQL 文件均指向 PostgreSQL 版，但 `docker/docker-compose.yml` 与 `docker/README.md` 中仍出现 MySQL 镜像和 MySQL 部署说明。使用 Docker 部署前需要按目标数据库版本核对 compose、SQL 脚本和后端 datasource。

## Fly.io 部署

根目录 `Dockerfile` 和 `fly.toml` 用于 Fly.io 部署：

- `Dockerfile`：多阶段构建，先构建 Vue 3 + Vite 管理端和学生端，再将产物复制到 Spring Boot static，最后打包运行 jar。
- `fly.toml`：Fly App 配置模板，默认内部端口为 `8000`。
- `docs/fly-managed-postgres-deployment.md`：Fly.io 冷启动按量部署、Postgres 挂载、初始化和日常停机步骤。

当前低成本部署使用可冷启动的 Fly Postgres App + Volume；如果需要托管运维和更高可靠性，再改用 Fly Managed Postgres。后端 `application-prod.yml` 支持 `SPRING_DATASOURCE_URL`、`SPRING_DATASOURCE_USERNAME`、`SPRING_DATASOURCE_PASSWORD`，并兼容 Fly 默认注入的 `DATABASE_URL=postgres://...`。

## 树莓派部署

`deploy/raspberry-pi` 保存树莓派运行环境专用部署资产：

- `deploy/raspberry-pi/xzs.service`：systemd 服务模板，包含低资源设备适配的 JVM、Undertow、Hikari 参数和生产环境变量占位符。
- `deploy/raspberry-pi/init-db.sh`：在树莓派 PostgreSQL 上创建或更新应用数据库用户、数据库并导入初始化脚本。
- `deploy/raspberry-pi/backup-db.sh`：使用 `pg_dump --format custom` 生成带时间戳的数据库备份，并按保留数量清理旧备份。
- `deploy/raspberry-pi/restore-db.sh`：从指定备份恢复数据库，要求显式确认后执行。
- `docs/raspberry-pi-deployment.md`：树莓派运行目录、部署资产安装、数据库初始化、systemd 启停、备份、恢复和健康检查说明。

树莓派普通运行时不承担 Maven 或前端构建任务；应在开发机或 CI 构建完成后，只复制后端 jar、SQL 脚本和运行所需部署资产。

## 集成部署提示

集成部署时，将管理端构建产物 `admin` 和学生端构建产物 `student` 放到 `source/xzs/src/main/resources/static` 后，再打包后端 jar。当前学生端构建产物来自 `frontend/apps/student/student`，管理端构建产物来自 `frontend/apps/admin/admin`。

仓库根目录提供了构建脚本：

- `scripts/sync-web-static.ps1`：同步两个 Web 构建产物到后端静态资源目录；学生端和管理端默认同步 Vue 3 + Vite 产物。
- `scripts/verify-admin-static.ps1`：验证后端 `/admin/index.html` 是否服务 Vue 3 + Vite 管理端，并复用管理端浏览器严格验证。
- `scripts/package-backend.ps1`：使用 Maven Wrapper、系统 Maven 或临时 Maven 打包后端。
- `scripts/build-all.ps1`：按管理端、学生端、静态资源同步、后端打包顺序执行集成构建。
- `scripts/measure-build.ps1`：记录各阶段耗时，便于对比优化效果。
