# 项目部署

当前仓库主线为 PostgreSQL + Flyway + Vue 3/Vite + Spring Boot。部署时以仓库内的构建脚本、Flyway 迁移和 PostgreSQL 初始化材料为准。

## 发布制品

- `release/java/xzs-3.9.0.jar`：后端 Spring Boot jar，也是 Docker Compose 示例使用的唯一发布 jar。
- `release/web/admin`：管理端静态资源。
- `release/web/student`：学生端静态资源。
- `sql/xzs-postgresql.sql`：PostgreSQL 初始化脚本；全新空库也可以直接由后端内置 Flyway 基线迁移初始化。

## 本地集成部署

在项目根目录构建前端静态资源并打包后端：

```powershell
.\scripts\build-all.ps1
```

脚本会依次构建 Vue 3 + Vite 管理端和学生端，将产物同步到 `source/xzs/src/main/resources/static`，再打包后端 jar。默认构建产物位置为：

- `frontend/apps/admin/admin`
- `frontend/apps/student/student`

准备 PostgreSQL 数据库后，可直接启动 jar。生产配置通过环境变量传入：

```powershell
$env:SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/xzs"
$env:SPRING_DATASOURCE_USERNAME = "xzs"
$env:SPRING_DATASOURCE_PASSWORD = "change-me"
java -Duser.timezone=Asia/Shanghai -Dspring.profiles.active=prod -jar .\release\java\xzs-3.9.0.jar
```

Linux 示例：

```bash
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/xzs \
SPRING_DATASOURCE_USERNAME=xzs \
SPRING_DATASOURCE_PASSWORD=change-me \
nohup java -Duser.timezone=Asia/Shanghai -Dspring.profiles.active=prod -jar release/java/xzs-3.9.0.jar > start.log 2>&1 &
```

访问地址：

- 学生端：`http://ip:8000/student`
- 管理端：`http://ip:8000/admin`

## 前后端分离部署

后端仍按生产 profile 连接 PostgreSQL 启动。前端可由 nginx 承载 `release/web/student` 和 `release/web/admin`，并将 `/api/` 代理到后端 8000 端口。

示例目录：

```text
/usr/local/xzs/web/student
/usr/local/xzs/web/admin
```

nginx 示例：

```nginx
server {
    listen 8001;
    server_name xzs;

    location / {
        root /usr/local/xzs/web/;
        index index.html;
    }

    location /api/ {
        proxy_pass http://localhost:8000;
    }
}
```

访问地址：

- 学生端：`http://ip:8001/student`
- 管理端：`http://ip:8001/admin`

## Docker Compose 部署

Docker Compose 示例位于 `docker/`，当前配置使用 PostgreSQL 和 `release/java/xzs-3.9.0.jar`。从仓库根目录执行：

```powershell
docker compose -f .\docker\docker-compose.yml up -d
```

或从 `docker` 目录执行：

```powershell
cd .\docker
docker compose up -d
```

首次启动时，PostgreSQL 容器会读取 `sql/xzs-postgresql.sql` 初始化数据库；后端容器通过 `SPRING_DATASOURCE_URL`、`SPRING_DATASOURCE_USERNAME`、`SPRING_DATASOURCE_PASSWORD` 连接该数据库。

## Fly.io 与树莓派部署

- Fly.io：使用根目录 `Dockerfile`、`fly.toml`，详细说明见 `docs/fly-managed-postgres-deployment.md`。
- 树莓派：使用 `deploy/raspberry-pi` 下的 systemd、数据库初始化、备份和恢复脚本，详细说明见 `docs/raspberry-pi-deployment.md`。

发布前可运行一致性校验：

```powershell
.\scripts\verify-release-consistency.ps1
```
