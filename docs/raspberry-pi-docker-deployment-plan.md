# Raspberry Pi Docker 部署方案

## 背景与现状

- 已确认：项目根目录有 `Dockerfile`，可以构建包含 Vue 3/Vite 管理端、学生端和 Spring Boot 后端的完整应用镜像。
- 已确认：`docker/docker-compose.yml` 是通用示例，使用 `eclipse-temurin:8-jre` 容器挂载 `release/java/xzs-3.9.0.jar` 运行，并用 PostgreSQL 容器初始化数据库。
- 已确认：项目生产配置可通过 `SPRING_DATASOURCE_URL`、`SPRING_DATASOURCE_USERNAME`、`SPRING_DATASOURCE_PASSWORD`、`SERVER_PORT`、Hikari 和 Undertow 环境变量注入。
- 目标设备：Raspberry Pi 4B 8GB，32G TF 卡。
- 关键约束：TF 卡容量和写入寿命有限，树莓派上不应执行 Maven、pnpm、Docker 多阶段构建等构建期任务。

## 结论

推荐采用“开发机或 CI 构建 `linux/arm64` 完整应用镜像并推送到镜像仓库，树莓派只通过 Docker Compose 拉取镜像并运行”的方案。

树莓派上运行两个容器：

1. `xzs-postgres`：PostgreSQL 15，数据绑定到 `/opt/apps/xzs/data/postgres`。
2. `xzs-app`：完整应用镜像，连接 `postgres` 服务，监听宿主机 `8000` 端口。

不推荐在树莓派上使用 `docker build`，也不推荐长期使用“Java 镜像 + 挂载 Jar”的方式作为生产部署主线。完整应用镜像更容易版本化、回滚和迁移。

## 需求拆解

### 1. 镜像构建与发布

- 当前现状：
  - 根目录 `Dockerfile` 已包含前端构建、后端 Maven 打包和最终 Java 运行镜像。
  - 树莓派 4B 通常使用 64 位系统时应选择 `linux/arm64` 镜像。
- 判断：
  - 构建过程会产生大量依赖缓存、临时文件和随机 I/O，不适合 32G TF 卡。
- 修改方案：
  - 在开发机或 CI 执行 buildx 构建并推送镜像。
  - 镜像标签使用不可变版本号，例如 `20260712-001`，不要只依赖 `latest`。
- 影响范围：
  - 需要一个可登录的镜像仓库，例如阿里云 ACR、GHCR 或 Docker Hub。
- 验证方案：
  - 开发机执行 `docker buildx build --platform linux/arm64 ... --push` 成功。
  - 树莓派执行 `docker pull <image>` 成功。

构建命令示例：

```powershell
docker buildx build --platform linux/arm64 -t <registry-host>/<namespace>/xzs:20260712-001 -f Dockerfile --push .
```

如果首次使用 buildx：

```powershell
docker buildx create --name xzs-arm64 --use
docker buildx inspect --bootstrap
```

### 2. 树莓派运行目录

- 当前现状：
  - 项目已有树莓派 systemd 文档使用 `/opt/xzs`。
  - Docker 应用更适合统一放在 `/opt/apps/<app-name>`。
- 判断：
  - 32G TF 卡上需要清晰区分配置、数据库、备份和日志，便于查看容量。
- 修改方案：
  - Docker 方案固定使用 `/opt/apps/xzs`。
- 影响范围：
  - 所有 compose、备份、恢复、更新命令都从该目录执行。
- 验证方案：
  - `df -h /opt/apps/xzs` 能看到剩余空间。
  - `du -h --max-depth=2 /opt/apps/xzs` 能定位数据库、备份、日志占用。

推荐目录：

```text
/opt/apps/xzs/
  .env
  docker-compose.yml
  init/
    01-xzs-postgresql.sql
  data/
    postgres/
  backups/
  logs/
    app/
```

初始化目录：

```bash
sudo mkdir -p /opt/apps/xzs/init /opt/apps/xzs/data/postgres /opt/apps/xzs/backups /opt/apps/xzs/logs/app
sudo chown -R $USER:$USER /opt/apps/xzs
chmod 700 /opt/apps/xzs/data/postgres /opt/apps/xzs/backups
```

把仓库里的 `sql/xzs-postgresql.sql` 复制到：

```text
/opt/apps/xzs/init/01-xzs-postgresql.sql
```

### 3. Compose 生产配置

- 当前现状：
  - 示例 compose 使用命名卷 `xzs-postgres-data`，并暴露 PostgreSQL 到 `127.0.0.1:5432`。
  - 示例 Java 容器没有限制 JVM 堆、Undertow 线程和 Hikari 连接池。
- 判断：
  - 对树莓派 4B 8GB，应用堆内存从 `512m` 起步更稳；如果并发和题库数据增长后仍有余量，再调到 `768m` 或 `1024m`。
  - PostgreSQL 不需要暴露宿主机端口，应用容器通过 compose 网络访问即可。
  - 使用绑定目录比命名卷更便于备份、迁移和观察 TF 卡空间。
- 修改方案：
  - 使用下面的 `docker-compose.yml`。
- 影响范围：
  - 首次启动时 PostgreSQL 会执行 `init/01-xzs-postgresql.sql`；这个初始化脚本只在空数据目录首次创建时执行。
- 验证方案：
  - `docker compose config` 成功。
  - `docker compose ps` 显示 `xzs-postgres` healthy，`xzs-app` running。

`/opt/apps/xzs/docker-compose.yml`：

```yaml
services:
  postgres:
    image: postgres:15-bookworm
    container_name: xzs-postgres
    restart: unless-stopped
    shm_size: 128mb
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C"
      TZ: Asia/Shanghai
    command:
      - postgres
      - -c
      - max_connections=30
      - -c
      - shared_buffers=256MB
      - -c
      - effective_cache_size=2GB
      - -c
      - maintenance_work_mem=128MB
      - -c
      - checkpoint_timeout=15min
      - -c
      - max_wal_size=512MB
      - -c
      - wal_compression=on
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
      - ./init/01-xzs-postgresql.sql:/docker-entrypoint-initdb.d/01-xzs-postgresql.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  app:
    image: ${XZS_IMAGE}
    container_name: xzs-app
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      SPRING_PROFILES_ACTIVE: prod
      SERVER_PORT: 8000
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB}
      SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER}
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD}
      SERVER_UNDERTOW_IO_THREADS: 2
      SERVER_UNDERTOW_WORKER_THREADS: 16
      SERVER_UNDERTOW_BUFFER_SIZE: 512
      SERVER_UNDERTOW_DIRECT_BUFFERS: "false"
      SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE: 4
      SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE: 1
      SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT: 30000
      SPRING_DATASOURCE_HIKARI_IDLE_TIMEOUT: 600000
      SPRING_DATASOURCE_HIKARI_MAX_LIFETIME: 1800000
      XZS_LOG_PATH: /app/logs
      TZ: Asia/Shanghai
    command:
      - java
      - -Xms128m
      - -Xmx512m
      - -XX:+UseSerialGC
      - -XX:MaxMetaspaceSize=192m
      - -XX:+ExitOnOutOfMemoryError
      - -Djava.security.egd=file:/dev/urandom
      - -Duser.timezone=Asia/Shanghai
      - -jar
      - /app/xzs.jar
    ports:
      - "8000:8000"
    volumes:
      - ./logs/app:/app/logs
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

`/opt/apps/xzs/.env`：

```dotenv
XZS_IMAGE=<registry-host>/<namespace>/xzs:20260712-001
POSTGRES_DB=xzs
POSTGRES_USER=xzs
POSTGRES_PASSWORD=replace-with-a-strong-password
```

创建 `.env` 后限制权限：

```bash
chmod 600 /opt/apps/xzs/.env
```

### 4. 首次部署

- 当前现状：
  - 树莓派只需要 Docker Engine 和 Compose v2。
- 判断：
  - 32G TF 卡不适合保留大量旧镜像和构建缓存。
- 修改方案：
  - 只在树莓派执行 `pull`、`up`、`logs`、`prune`。
- 影响范围：
  - 如果镜像仓库是私有仓库，需要先在树莓派执行 `docker login`。
- 验证方案：
  - `curl -f http://127.0.0.1:8000/actuator/health` 返回成功。
  - 局域网访问 `/student` 和 `/admin` 成功。

安装 Docker：

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

重新登录 SSH 后验证：

```bash
docker version
docker compose version
```

登录镜像仓库：

```bash
docker login <registry-host>
```

启动：

```bash
cd /opt/apps/xzs
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker logs --tail=80 xzs-app
curl -f http://127.0.0.1:8000/actuator/health
```

局域网访问：

```text
http://<raspberry-pi-ip>:8000/student
http://<raspberry-pi-ip>:8000/admin
```

### 5. 更新与回滚

- 当前现状：
  - Docker 镜像天然适合按标签发布。
- 判断：
  - `latest` 不利于回滚和确认当前运行版本。
- 修改方案：
  - 每次发布使用新镜像标签，更新 `.env` 中的 `XZS_IMAGE` 后重启应用。
- 影响范围：
  - 数据库容器和数据目录不随应用镜像更新而删除。
- 验证方案：
  - 更新后检查健康接口、关键页面和日志。
  - 回滚时把 `XZS_IMAGE` 改回上一版并 `docker compose up -d`。

更新：

```bash
cd /opt/apps/xzs
cp .env .env.$(date +%Y%m%d-%H%M%S).bak
nano .env
docker compose pull app
docker compose up -d app
docker logs --tail=80 xzs-app
curl -f http://127.0.0.1:8000/actuator/health
docker image prune -f
```

回滚：

```bash
cd /opt/apps/xzs
nano .env
docker compose pull app
docker compose up -d app
docker logs --tail=80 xzs-app
```

### 6. 备份与恢复

- 当前现状：
  - 数据库是核心资产，不能只依赖 Docker volume 或 TF 卡。
- 判断：
  - 32G TF 卡上本地备份只保留少量最近版本，长期备份应复制到电脑、NAS、移动硬盘或云端。
- 修改方案：
  - 使用 `pg_dump --format custom` 备份。
  - 本地保留最近 3 份，外部至少保留 7 份或按教学周期保留。
- 影响范围：
  - 恢复前应停止应用容器，避免连接占用和写入竞争。
- 验证方案：
  - 定期在另一台机器或临时库执行一次恢复演练。

备份：

```bash
cd /opt/apps/xzs
set -a
. ./.env
set +a
mkdir -p backups
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" xzs-postgres pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --format custom \
  --no-owner \
  --no-privileges \
  > "backups/xzs-$(date +%Y%m%d-%H%M%S).dump"
find backups -maxdepth 1 -type f -name 'xzs-*.dump' -printf '%T@ %p\n' | sort -rn | awk 'NR>3 {print $2}' | xargs -r rm -f
```

恢复：

```bash
cd /opt/apps/xzs
set -a
. ./.env
set +a
docker compose stop app
cat backups/<backup-file>.dump | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" xzs-postgres pg_restore \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges
docker compose start app
docker logs --tail=80 xzs-app
```

### 7. 32G TF 卡容量与写入控制

- 当前现状：
  - Docker 镜像、容器日志、PostgreSQL WAL、数据库数据和备份都会占用 TF 卡。
- 判断：
  - 32G TF 卡可以运行，但需要控制构建缓存、旧镜像、日志和备份数量。
- 修改方案：
  - 不在树莓派构建镜像。
  - Compose 中限制 json 日志大小。
  - 每次更新后执行 `docker image prune -f`。
  - 本地数据库备份只保留最近 3 份，并定期复制到外部存储。
  - 如果数据量增长或使用频繁，优先把 `/opt/apps/xzs/data/postgres` 迁移到 USB 3.0 SSD。
- 影响范围：
  - TF 卡容量低于 20% 时，PostgreSQL 和 Docker 都更容易出问题。
- 验证方案：
  - 每周检查一次 `df -h`、`docker system df` 和 `du -h --max-depth=2 /opt/apps/xzs`。

常用检查：

```bash
df -h
docker system df
du -h --max-depth=2 /opt/apps/xzs
docker stats --no-stream xzs-app xzs-postgres
free -h
vcgencmd measure_temp
```

不要在生产数据未备份时执行：

```bash
docker compose down -v
```

这个命令会删除匿名卷或命名卷；虽然本方案使用绑定目录，仍容易造成误操作。

## 执行顺序

1. 确认树莓派系统是 64 位，并安装 Docker Engine 与 Compose v2。
2. 在镜像仓库创建 `xzs` 镜像仓库。
3. 在开发机用 `docker buildx build --platform linux/arm64 ... --push` 构建并推送应用镜像。
4. 在树莓派创建 `/opt/apps/xzs` 目录和 `.env`、`docker-compose.yml`。
5. 复制 `sql/xzs-postgresql.sql` 到 `/opt/apps/xzs/init/01-xzs-postgresql.sql`。
6. 在树莓派执行 `docker compose config && docker compose pull && docker compose up -d`。
7. 验证健康检查、学生端、管理端、日志、资源占用。
8. 配置数据库备份流程，并把备份复制到树莓派以外的位置。

## 风险与待确认

- 镜像仓库待确认：阿里云 ACR、GHCR 或 Docker Hub 均可；私有仓库需要树莓派执行 `docker login`。
- 公网访问待确认：如果只在局域网使用，直接暴露 `8000` 即可；如果公网访问，应在前面加反向代理和 HTTPS。
- 备份目标待确认：32G TF 卡不应作为唯一备份位置。
- 数据初始化策略待确认：`init/01-xzs-postgresql.sql` 只在空数据库目录首次启动时执行；已有数据库升级应依赖应用内 Flyway 迁移和正式备份。
- 性能参数需要上线后观察：初始 JVM `-Xmx512m`、Hikari 最大连接数 `4`；如果 8GB 内存余量稳定且并发增加，可逐步调大。

