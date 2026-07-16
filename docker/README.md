# Docker Compose 部署

本目录提供当前 PostgreSQL 版的 Docker Compose 示例。后端容器直接运行仓库发布制品 `release/java/xzs-3.9.0.jar`，数据库容器首次启动时读取 `sql/xzs-postgresql.sql` 初始化数据。

## 前置条件

- 已安装 Docker 与 Docker Compose v2。
- `release/java/xzs-3.9.0.jar` 已存在。
- `sql/xzs-postgresql.sql` 已存在。

## 从仓库根目录启动

```powershell
docker compose -f .\docker\docker-compose.yml up -d
```

查看日志：

```powershell
docker compose -f .\docker\docker-compose.yml logs -f java
```

停止服务：

```powershell
docker compose -f .\docker\docker-compose.yml down
```

## 从 docker 目录启动

```powershell
cd .\docker
docker compose up -d
```

查看日志：

```powershell
docker compose logs -f java
```

停止服务：

```powershell
docker compose down
```

## 服务说明

- `postgres`：PostgreSQL 15，默认创建 `xzs` 数据库和 `xzs` 用户，数据持久化到命名卷 `xzs-postgres-data`。
- `java`：Java 8 运行环境，挂载 `../release/java` 到 `/usr/local/xzs/release:ro`，运行 `/usr/local/xzs/release/xzs-3.9.0.jar`。
- 后端生产配置通过 `SPRING_DATASOURCE_URL`、`SPRING_DATASOURCE_USERNAME`、`SPRING_DATASOURCE_PASSWORD` 注入。

访问地址：

- 学生端：`http://ip:8000/student`
- 管理端：`http://ip:8000/admin`

如需重新初始化数据库，需要先停止服务并删除 `xzs-postgres-data` 数据卷。删除数据卷会清空数据库，请先备份。

## 运行参数参考

树莓派或低资源主机上优先通过 `docker/docker-compose.yml` 的 `java.command` 和环境变量调整运行参数。改动前先记录当前 `docker compose ps`、`docker compose logs --tail 200 java` 和数据库连接池日志，避免把网络缓存、冷启动或数据库慢查询误判为 JVM 问题。

JVM 参数可从小内存保守值开始，例如：

```yaml
command: >
  sh -c "java -Duser.timezone=Asia/Shanghai -Dspring.profiles.active=prod
  -Xms128m -Xmx384m -XX:+UseSerialGC
  -jar /usr/local/xzs/release/xzs-3.9.0.jar"
```

Undertow 和 Hikari 参数建议通过环境变量覆盖 Spring Boot 配置，按实际并发逐步调整：

```yaml
environment:
  SERVER_UNDERTOW_IO_THREADS: 2
  SERVER_UNDERTOW_WORKER_THREADS: 16
  SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE: 5
  SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE: 1
  SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT: 30000
```

如果站点前面接了 Cloudflare，性能排查时同时检查：

- 静态资源是否命中缓存：查看响应头 `cf-cache-status`、`cache-control`、`etag`。
- HTML 是否被错误缓存：管理端、学生端入口 HTML 通常不应长时间强缓存。
- 首次访问慢是否来自后端冷启动、数据库唤醒或 Cloudflare 回源，而不是前端包体。
- 变更静态资源后是否需要清理 Cloudflare 缓存或等待哈希资源自然更新。

## 数据备份

Docker 部署时 PostgreSQL 数据保存在命名卷 `xzs-postgres-data`。日常备份建议使用 `pg_dump --format custom` 生成逻辑备份，不建议直接复制 Docker volume 作为唯一备份。

如果树莓派是主服务节点，可以继续保留 Fly.io 作为低成本冷启动冷备节点：定期从树莓派导出 `.dump`，再恢复到 Fly Postgres。完整流程见 `docs/fly-to-raspberry-pi-data-migration-plan.md`。

当前生产约定是：更新远端数据时先更新树莓派 Docker PostgreSQL，验证 `https://gesp-csp-quiz.randolph87.top` 后，再把树莓派 dump 同步到 Fly 冷备。不要把 Fly 当作默认写入目标。

手动备份示例：

```sh
sudo mkdir -p /opt/xzs/backups
timestamp="$(date +%Y%m%d-%H%M%S)"
docker exec -e PGPASSWORD='<db-password>' xzs-postgres pg_dump \
  --host 127.0.0.1 \
  --port 5432 \
  --username xzs \
  --dbname xzs \
  --format custom \
  --no-owner \
  --no-privileges \
  > "/opt/xzs/backups/xzs-${timestamp}.dump"
```

`<db-password>` 以实际 Compose 配置为准；仓库示例值为 `xzs_change_me`，生产环境应替换。

恢复备份时先停止应用容器，保留 PostgreSQL 容器运行。仓库示例容器名为 `xzs-java`，当前树莓派生产部署可能是 `xzs-app`，执行前先用 `docker ps` 确认：

```sh
APP_CONTAINER=xzs-app
docker stop "$APP_CONTAINER"
docker cp /opt/xzs/backups/<backup-file>.dump xzs-postgres:/tmp/xzs-restore.dump
docker exec -e PGPASSWORD='<db-password>' xzs-postgres pg_restore \
  --host 127.0.0.1 \
  --port 5432 \
  --username xzs \
  --dbname xzs \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  /tmp/xzs-restore.dump
docker start "$APP_CONTAINER"
```

恢复后建议执行：

```sh
docker compose -f ./docker/docker-compose.yml logs --tail 100 postgres
docker compose -f ./docker/docker-compose.yml logs --tail 100 java
docker exec -e PGPASSWORD='<db-password>' xzs-postgres psql \
  --host 127.0.0.1 \
  --username xzs \
  --dbname xzs \
  --command "select count(*) from t_question;"
```

## Fly 冷备

树莓派作为主节点时，Fly.io 可以保留为冷备环境。建议只在明确维护窗口内执行同步：

1. 树莓派主库执行 `pg_dump --format custom --no-owner --no-privileges`。
2. 将 `.dump` 上传到受控位置或本地开发机。
3. 停止 Fly 应用写入流量，确认不会产生双写。
4. 对 Fly Postgres 执行 `pg_restore --clean --if-exists --no-owner --no-privileges`。
5. 启动 Fly 应用后做只读抽样检查，再保持冷备停机或低成本待机。

不要把 Fly 冷备恢复当作默认日常备份替代品；主节点仍应保留本地定时备份和至少一份异地备份。

后续文档或脚本中提到“远端数据更新”时，默认目标是树莓派主站；Fly 只接收从树莓派导出的冷备快照。

## 从 Fly.io 迁移到树莓派 Docker

如果树莓派使用 Docker Compose 作为长期主环境，按 `docs/fly-to-raspberry-pi-data-migration-plan.md` 执行。该文档包含演练迁移、最终停写切换、Fly 冷备同步、本机定时备份和恢复演练策略。
