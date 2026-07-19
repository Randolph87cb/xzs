# Fly.io 测试环境部署与历史 Fly Postgres 说明

当前状态：部署环境已经固定为三层：树莓派是生产环境，Fly.io 是测试环境，本地是开发环境。树莓派生产环境连接 Neon `production` branch；Fly 测试环境和本地开发环境连接 Neon `test` branch。本文保留 Fly Postgres 冷启动方案作为历史方案和回滚参考；新的 Fly Web App 部署默认只配置 Neon `test` branch secret，不再创建或挂载 Fly Postgres 主库。

## 环境职责

| 环境 | 入口 | 数据库 | 用途 |
| --- | --- | --- | --- |
| 生产环境 | 树莓派主站，例如 `https://gesp-csp-quiz.randolph87.top` | Neon `production` branch | 对学生和老师开放的正式服务 |
| 测试环境 | Fly App `gesp-csp-quiz`，默认 `https://gesp-csp-quiz.fly.dev` | Neon `test` branch | 远端测试、预发布验收、AI 审核联调 |
| 开发环境 | 本地 `scripts/start-local-neon.ps1` | Neon `test` branch | 本地开发和浏览器验收 |

Fly 的 Spring profile 仍使用 `prod`，因为它运行的是打包后的生产形态 Jar；环境属性由连接到 Neon `test` branch 来区分。不要把 Fly 配成 Neon `production` branch，也不要把树莓派生产环境连接到 Neon `test` branch。

## 架构

- Fly App：运行 Spring Boot jar，端口 `8000`，内置管理端和学生端 Vue 3 + Vite 静态资源。
- Neon PostgreSQL：当前业务数据库。树莓派生产环境使用 Neon `production` branch；Fly 测试环境和本地开发环境使用 Neon `test` branch。
- Fly Postgres App：历史方案，曾使用带 Volume 的 Postgres Machine 持久化业务数据库并开启 `FLY_SCALE_TO_ZERO=1` 支持冷启动；当前旧 App 已停止，仅作为迁移来源或回滚参考。
- 文件上传：当前关闭题目图片、富文本图片、头像等上传入口，不依赖七牛或其他对象存储。

Fly App 的普通文件系统不是持久化存储。Fly Volume 可持久化某台 Machine 的本地目录，但不能自动多机共享；本项目核心业务数据应放在 Postgres。当前没有运行时上传文件需要持久化。

当前 Fly 测试部署目标是 Fly Web App 低成本冷启动 + Neon `test` branch：

- Web App 设置 `auto_start_machines = true`、`auto_stop_machines = "stop"`、`min_machines_running = 0`。
- Web Machine 可以停机，访问应用时再启动。
- 数据库由 Neon 托管，不再由 Fly Postgres Machine 和 Volume 承载。
- Machine 计算资源按运行时间计费；历史 Fly Postgres Volume 如果保留，即使停机也会继续按容量计费。

如果后续重新评估数据库托管方式，可以在 Neon、Supabase、Fly Managed Postgres 之间单独做迁移方案；不要在没有确认的情况下恢复 Fly Postgres 作为主库。

## 文件

- `Dockerfile`：Fly 远端构建入口。它会先构建两个 Vue 3 + Vite 前端，再将产物复制进 Spring Boot static，最后打包 jar。
- `fly.toml`：Fly App 配置，默认内部端口为 `8000`。
- `source/xzs/src/main/resources/application-prod.yml`：生产数据库配置支持环境变量。
- `FlyPostgresEnvironment`：兼容 `SPRING_DATASOURCE_URL=postgresql://...`、`SPRING_DATASOURCE_URL=postgres://...` 和 Fly 注入的 `DATABASE_URL=postgres://...`，启动时转换为 Spring JDBC datasource 属性，并移除 `channel_binding` 参数。
- `.env.neon-test.example`：本地构建服务测试连接 Neon `test` branch 的环境变量模板。

## 当前部署命名

当前项目名为“信息学客观题一本通 / GESP/CSP 客观题训练”。Fly Web App 采用短且直观的英文名：

- Fly App：`gesp-csp-quiz`
- 默认域名：`https://gesp-csp-quiz.fly.dev`
- Neon 生产分支：`production`
- Neon 测试分支：`test`
- 历史 Fly Postgres App：`xzs-pg-cb867393296`，当前已停止，仅作为历史迁移来源或回滚参考。
- 历史 Fly 业务库：`xzs_cb867393296`

`gesp-csp-quiz` 直接对应 GESP/CSP 训练场景，便于记忆和分享。Neon 数据库连接串、密码和 Fly secrets 不写入仓库文档；只在 `.env.neon-test`、本机环境变量或 Fly secrets 中保存。

## Fly 测试环境 Neon 配置

Fly Web App 使用 Neon 原始 URL 形式配置数据库。Fly 只允许使用 Neon `test` branch。连接串包含用户名和密码时，不需要额外设置 `SPRING_DATASOURCE_USERNAME` 和 `SPRING_DATASOURCE_PASSWORD`。

推荐使用统一脚本从被 Git 忽略的 `.env.neon-test` 导入测试环境 secret 并部署：

```powershell
.\scripts\deploy-fly-neon-test.ps1
```

脚本会读取 `.env.neon-test` 中的 `SPRING_DATASOURCE_URL`、Hikari 连接池配置和 `XZS_AI_CONFIG_SECRET`，通过 `flyctl secrets import --stage` 写入 Fly，再执行 `flyctl deploy -a gesp-csp-quiz`，最后运行远端健康检查。脚本只打印 secret 名，不打印 secret 值。

如果只想导入 secret 和部署，不跑远端检查：

```powershell
.\scripts\deploy-fly-neon-test.ps1 -SkipRemoteCheck
```

`.env.neon-test` 内容示例：

```powershell
SPRING_PROFILES_ACTIVE=prod
SPRING_DATASOURCE_URL=postgresql://<user>:<password>@<test-branch-host>/<database>?sslmode=require&channel_binding=require
SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE=3
SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE=1
XZS_AI_CONFIG_SECRET=<32 字符或更长的本地/测试环境密钥>
```

`.env.neon-test` 已被 Git 忽略。不要把完整 Neon URL、密码或 Fly secrets 写入可提交文件。

如果曾经挂载过 Fly Postgres，确认不再使用旧连接后移除旧 `DATABASE_URL`：

```powershell
fly secrets unset DATABASE_URL -a gesp-csp-quiz
```

Neon branch 使用约定：

- 树莓派生产环境连接 `production` branch。
- Fly 测试环境和本地开发环境连接 `test` branch。
- 需要复制生产数据时，在 Neon 控制台从 `production` reset 或重建 `test` branch；该操作会清空 `test` branch 当前写入，执行前先确认测试数据不需要保留。

## 历史 Fly Postgres 方案

以下步骤只用于历史回滚或重新启用 Fly Postgres 时参考；当前 Neon 部署不需要执行这些步骤。

### 首次部署

安装并登录 flyctl 后，在仓库根目录执行：

```powershell
fly launch --copy-config --no-deploy --name <your-unique-app-name>
```

`--no-deploy` 可以避免数据库 secret 注入前先部署一次并失败。如果不使用 `--name`，需要先把 `fly.toml` 里的 `app` 改成你的唯一 Fly app 名。当前仓库默认使用 `app = "gesp-csp-quiz"`。

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

如果要让新的 Web App 复用当前历史数据库数据，需显式指定已有数据库名：

```powershell
fly postgres attach xzs-pg-cb867393296 -a gesp-csp-quiz --database-name xzs_cb867393296 --database-user gesp_csp_quiz --yes
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
fly deploy -a gesp-csp-quiz
```

部署后执行远端验收测试，确认 Spring Boot 已启动、数据库可连通，并且管理端和学生端静态入口是本次打包出的 Vite 产物：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://gesp-csp-quiz.fly.dev"
```

如果是低成本冷启动部署，首次请求可能需要等待 Web Machine 和 Postgres Machine 启动。脚本默认最多重试 30 次，每次间隔 10 秒；任一检查失败会以非 0 退出码结束，适合接到 CI 或发布脚本的 `fly deploy` 后面。

```powershell
fly deploy -a gesp-csp-quiz
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://gesp-csp-quiz.fly.dev" -RetryCount 45 -RetryDelaySeconds 10
```

减少常驻实例数：

```powershell
fly scale count 1 -a gesp-csp-quiz --yes
```

确认 Web 冷启动配置：

```powershell
fly config show -a gesp-csp-quiz
```

确认输出中 `auto_start_machines` 为 `true`、`auto_stop_machines` 为 `true` 或 `stop`、`min_machines_running` 为 `0`。

## Fly 测试环境日常发布

代码变更后重新部署测试环境，优先使用统一脚本：

```powershell
.\scripts\deploy-fly-neon-test.ps1
```

查看日志：

```powershell
fly logs -a gesp-csp-quiz
```

生产环境 logback 会同时写入控制台和文件，因此 `fly logs` 可以看到应用日志。文件日志默认写入 `/tmp/xzs/logs`，不作为持久化归档。

打开 Fly 测试环境：

```powershell
fly open -a gesp-csp-quiz
```

机器可判定的部署后检查：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://gesp-csp-quiz.fly.dev"
```

手动停机进入冷启动状态：

```powershell
fly machine list -a gesp-csp-quiz
fly machine stop <web-machine-id> -a gesp-csp-quiz
```

停机后再次访问应用 URL，Fly 会按需启动 Web Machine。当前 Fly 测试数据库在 Neon `test` branch，不需要停止 Fly Postgres Machine。历史 Fly Postgres App 如需保留回滚参考，可保持 stopped；销毁 App 或 Volume 前必须再次确认。

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

- Neon PostgreSQL：当前业务数据库；树莓派生产环境使用 `production` branch，Fly 测试和本地开发使用 `test` branch。
- Fly Postgres App + Volume：历史冷启动按量方案，旧 App 当前已停止，仅作为迁移来源或回滚参考。
- Managed Postgres：适合需要托管运维、备份和更高数据库可靠性的生产部署，但不符合最低成本冷启动目标。
- 文件上传：当前已关闭，不需要对象存储；历史题目中已保存的外链图片仍可按原 URL 展示。
- Fly Volume：只在确实需要本地持久目录时使用，例如单机日志归档；不要用它存多实例共享上传文件。
- 容器本地磁盘：只用于临时文件和运行时缓存。
