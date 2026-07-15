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

## 数据备份

Docker 部署时 PostgreSQL 数据保存在命名卷 `xzs-postgres-data`。日常备份建议使用 `pg_dump --format custom` 生成逻辑备份，不建议直接复制 Docker volume 作为唯一备份。

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

恢复备份时先停止 Java 容器，保留 PostgreSQL 容器运行：

```sh
docker stop xzs-java
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
docker start xzs-java
```

## 从 Fly.io 迁移到树莓派 Docker

如果树莓派使用 Docker Compose 作为长期主环境，按 `docs/fly-to-raspberry-pi-data-migration-plan.md` 执行。该文档包含演练迁移、最终停写切换、Fly 回滚保留、本机定时备份和异机备份策略。
