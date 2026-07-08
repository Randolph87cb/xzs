# Fly.io 冷启动按量部署说明

## 架构

- Fly App：运行 Spring Boot jar，端口 `8000`，内置管理端和学生端 Vue 3 + Vite 静态资源。
- Fly Postgres App：使用带 Volume 的 Postgres Machine 持久化业务数据库，并开启 `FLY_SCALE_TO_ZERO=1` 支持冷启动。
- 文件上传：当前关闭题目图片、富文本图片、头像等上传入口，不依赖七牛或其他对象存储。

Fly App 的普通文件系统不是持久化存储。Fly Volume 可持久化某台 Machine 的本地目录，但不能自动多机共享；本项目核心业务数据应放在 Postgres。当前没有运行时上传文件需要持久化。

当前部署目标是低成本冷启动：

- Web App 设置 `auto_start_machines = true`、`auto_stop_machines = "stop"`、`min_machines_running = 0`。
- Postgres App 设置 secret `FLY_SCALE_TO_ZERO=1`。
- Web 和数据库 Machine 都可以停机，访问应用时再启动。
- Machine 计算资源按运行时间计费；Postgres Volume 存储即使停机也会继续按容量计费。

如果需要 Fly 官方托管运维、备份和更少数据库维护工作，可以改用 Fly Managed Postgres；它不适合当前“冷启动、按量付费优先”的目标。

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

创建可冷启动的 Fly Postgres：

```powershell
fly postgres create --name <your-postgres-app-name> --region nrt --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 1
```

开启 Postgres 冷启动：

```powershell
fly secrets set FLY_SCALE_TO_ZERO=1 -a <your-postgres-app-name>
```

把数据库挂到应用：

```powershell
fly postgres attach <your-postgres-app-name> -a <your-unique-app-name>
```

`fly postgres attach` 会把连接串写入应用 secret。项目已支持 Fly 默认的 `DATABASE_URL`，也支持显式设置 Spring datasource：

```powershell
fly secrets set `
  SPRING_DATASOURCE_URL="jdbc:postgresql://<host>:5432/<database>" `
  SPRING_DATASOURCE_USERNAME="<user>" `
  SPRING_DATASOURCE_PASSWORD="<password>" `
  -a <your-unique-app-name>
```

导入数据库初始化脚本。如果本地有 `psql`，可以通过代理连接后导入：

```powershell
fly proxy 15432:5432 -a <your-postgres-app-name>
```

另开一个终端执行：

```powershell
psql "postgres://<user>:<password>@localhost:15432/<database>" -f .\sql\xzs-postgresql.sql
```

部署应用：

```powershell
fly deploy -a <your-unique-app-name>
```

部署后执行远端验收测试，确认 Spring Boot 已启动、数据库可连通，并且管理端和学生端静态入口是本次打包出的 Vite 产物：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://<your-unique-app-name>.fly.dev"
```

如果是低成本冷启动部署，首次请求可能需要等待 Web Machine 和 Postgres Machine 启动。脚本默认最多重试 30 次，每次间隔 10 秒；任一检查失败会以非 0 退出码结束，适合接到 CI 或发布脚本的 `fly deploy` 后面。

```powershell
fly deploy -a <your-unique-app-name>
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://<your-unique-app-name>.fly.dev" -RetryCount 45 -RetryDelaySeconds 10
```

减少常驻实例数：

```powershell
fly scale count 1 -a <your-unique-app-name> --yes
```

确认 Web 冷启动配置：

```powershell
fly config show -a <your-unique-app-name>
```

确认输出中 `auto_start_machines` 为 `true`、`auto_stop_machines` 为 `true` 或 `stop`、`min_machines_running` 为 `0`。

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

机器可判定的部署后检查：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://<your-unique-app-name>.fly.dev"
```

手动停机进入冷启动状态：

```powershell
fly machine list -a <your-unique-app-name>
fly machine stop <web-machine-id> -a <your-unique-app-name>

fly machine list -a <your-postgres-app-name>
fly machine stop <postgres-machine-id> -a <your-postgres-app-name>
```

停机后再次访问应用 URL，Fly 会按需启动 Web Machine；应用连接数据库时会唤起 Postgres Machine。

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

- Fly Postgres App + Volume：当前冷启动按量方案，用于账号、题目、试卷、答卷、成绩、消息等业务数据。
- Managed Postgres：适合需要托管运维、备份和更高数据库可靠性的生产部署，但不符合最低成本冷启动目标。
- 文件上传：当前已关闭，不需要对象存储；历史题目中已保存的外链图片仍可按原 URL 展示。
- Fly Volume：只在确实需要本地持久目录时使用，例如单机日志归档；不要用它存多实例共享上传文件。
- 容器本地磁盘：只用于临时文件和运行时缓存。
