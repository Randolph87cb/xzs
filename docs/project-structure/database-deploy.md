# 数据库与部署资产

`sql/xzs-postgresql.sql` 是 PostgreSQL 初始化脚本，包含序列、表结构和初始化数据。`sql/README.md` 只保留数据库下载地址说明。

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

## 集成部署提示

集成部署时，将管理端构建产物 `admin` 和学生端构建产物 `student` 放到 `source/xzs/src/main/resources/static` 后，再打包后端 jar。
