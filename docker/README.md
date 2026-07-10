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
