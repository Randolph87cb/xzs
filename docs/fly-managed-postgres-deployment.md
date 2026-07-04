# Fly.io + Managed Postgres 部署说明

## 架构

- Fly App：运行 Spring Boot jar，端口 `8000`，内置管理端和学生端 Vue 3 + Vite 静态资源。
- Fly Managed Postgres：持久化业务数据库。
- 对象存储：题目图片、富文本图片、头像等继续使用七牛或其他 S3 兼容对象存储，不写入 Fly App 本地磁盘。

Fly App 的普通文件系统不是持久化存储。Fly Volume 可持久化某台 Machine 的本地目录，但不能自动多机共享；本项目核心业务数据应放在 Managed Postgres，上传文件应放对象存储。

## 文件

- `Dockerfile`：Fly 远端构建入口。它会先构建两个 Vue 3 + Vite 前端，再将产物复制进 Spring Boot static，最后打包 jar。
- `fly.toml`：Fly App 配置，默认内部端口为 `8000`。
- `source/xzs/src/main/resources/application-prod.yml`：生产数据库配置支持环境变量。
- `FlyPostgresEnvironment`：兼容 Fly 注入的 `DATABASE_URL=postgres://...`，启动时转换为 Spring JDBC datasource 属性。

## 首次部署

安装并登录 flyctl 后，在仓库根目录执行：

```powershell
fly launch --copy-config --no-deploy --name <your-unique-app-name>
```

`--no-deploy` 可以避免数据库 secret 注入前先部署一次并失败。如果不使用 `--name`，需要先把 `fly.toml` 里的 `app = "xzs"` 改成你的唯一 Fly app 名。

创建 Fly Managed Postgres：

```powershell
fly mpg create
```

创建完成后，把数据库挂到应用：

```powershell
fly mpg attach <cluster-id> -a <your-unique-app-name>
```

`fly mpg attach` 会把连接串写入应用 secret。项目已支持 Fly 默认的 `DATABASE_URL`，也支持显式设置 Spring datasource：

```powershell
fly secrets set `
  SPRING_DATASOURCE_URL="jdbc:postgresql://<host>:5432/<database>" `
  SPRING_DATASOURCE_USERNAME="<user>" `
  SPRING_DATASOURCE_PASSWORD="<password>" `
  -a <your-unique-app-name>
```

如果要覆盖七牛或其他对象存储配置，使用 secrets：

```powershell
fly secrets set `
  XZS_QN_URL="<public-file-url>" `
  XZS_QN_BUCKET="<bucket>" `
  XZS_QN_ACCESS_KEY="<access-key>" `
  XZS_QN_SECRET_KEY="<secret-key>" `
  -a <your-unique-app-name>
```

导入数据库初始化脚本：

```powershell
fly mpg connect <cluster-id>
```

进入 psql 后执行 `sql/xzs-postgresql.sql`。如果本地有 `psql`，也可以使用 Fly 提供的连接串导入：

```powershell
psql "<postgres-connection-url>" -f .\sql\xzs-postgresql.sql
```

部署应用：

```powershell
fly deploy -a <your-unique-app-name>
```

## 日常发布

代码变更后重新部署：

```powershell
fly deploy -a <your-unique-app-name>
```

查看日志：

```powershell
fly logs -a <your-unique-app-name>
```

生产环境 logback 会同时写入控制台和文件，因此 `fly logs` 可以看到应用日志。文件日志默认写入 `/tmp/xzs/logs`，不作为持久化归档。

打开应用：

```powershell
fly open -a <your-unique-app-name>
```

## 本地验证

部署前建议至少运行：

```powershell
node .\scripts\test-markdown-renderer.js
pnpm --dir frontend typecheck
.\scripts\build-all.ps1 -SkipInstall
```

构建 Docker 镜像做本地验证：

```powershell
docker build -t xzs-fly .
```

如果要本地用 Fly 格式的 `DATABASE_URL` 验证转换逻辑：

```powershell
docker run --rm -p 8000:8000 `
  -e DATABASE_URL="postgres://postgres:123456@host.docker.internal:5432/xzs" `
  xzs-fly
```

## 持久化选择

- Managed Postgres：账号、题目、试卷、答卷、成绩、消息等业务数据。
- 对象存储：图片、附件、头像、富文本媒体资源。
- Fly Volume：只在确实需要本地持久目录时使用，例如单机日志归档；不要用它存多实例共享上传文件。
- 容器本地磁盘：只用于临时文件和运行时缓存。
