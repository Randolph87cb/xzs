# Fly.io 到树莓派 Docker 数据迁移与备份方案

## 背景与现状

- 已确认 Fly.io 当前 Web App 为 `gesp-csp-quiz`，默认访问地址为 `https://gesp-csp-quiz.fly.dev`。
- 已确认 Fly Postgres App 为 `xzs-pg-cb867393296`，当前业务库为 `xzs_cb867393296`。
- 已确认树莓派当前采用 Docker Compose 部署，配置入口为 `docker/docker-compose.yml`。
- 仓库示例 Docker Compose 中 PostgreSQL 服务为 `postgres`，容器名为 `xzs-postgres`，Java 服务为 `java`，容器名为 `xzs-java`，数据库卷为 `xzs-postgres-data`。实际树莓派生产部署可能使用不同应用容器名；2026-07-16 迁移时实际应用容器为 `xzs-app`。
- 已确认 Docker Compose 默认数据库名、用户名、密码分别为 `xzs`、`xzs`、`xzs_change_me`。生产环境应以树莓派实际 `docker-compose.yml` 或 `.env` 中的密码为准。
- 已确认远端部署检查脚本为 `scripts/test-remote-deployment.ps1`，会检查 `/api/health`、`/student/index.html` 和 `/admin/index.html`。
- 已确认 2026-07-16 之后树莓派主站为 `https://gesp-csp-quiz.randolph87.top`，后续文档中未特别说明时，“远端”“线上”“主站”默认指这个树莓派 Docker 部署。
- 推断当前核心业务数据都在 PostgreSQL 中；项目文档已说明当前关闭运行时上传入口，不依赖 Fly App 本地磁盘持久化。

## 结论

推荐采用“一次演练迁移 + 一次停写最终迁移 + 树莓派主服务 + Fly.io 冷备服务 + 本机备份文件”的方式。切换完成后，以树莓派 URL 为主入口；Fly.io 保留为低成本冷启动备用节点，并定期从树莓派同步数据库。Fly 平时不承接用户写入，只有树莓派故障或维护时才临时切过去。

Fly 作为备份的定位是“冷备/备用服务节点”，不是自动实时备份。它能降低额外备份机器成本，但恢复点取决于最近一次从树莓派同步到 Fly 的时间。例如每日凌晨同步一次，最坏会丢失当天同步后到故障发生前的数据；每 6 小时同步一次，最坏丢失窗口约为 6 小时。

本文以 Docker Compose 部署为准，不使用 `deploy/raspberry-pi/*.sh` 和 systemd 服务命令。那些脚本适用于非 Docker 的 Jar 直部署。

## 日常约定：远端数据更新与 Fly 备份

2026-07-16 迁移完成后，日常数据运维的默认方向已经改变：

- 更新远端数据：更新树莓派主库，也就是 `https://gesp-csp-quiz.randolph87.top` 背后的 Docker PostgreSQL。
- 备份远端数据：从树莓派主库导出 `.dump`，再恢复到 Fly Postgres，形成 Fly 冷备。
- Fly 的角色：低成本冷启动冷备和应急入口，不是日常主写入环境。
- 禁止默认写 Fly：除非明确执行“同步到 Fly 冷备”或“灾难切换到 Fly”，否则题库同步、解析回写、后台数据修复都不应直接写 Fly。

推荐的日常顺序：

1. 在本地生成 SQL 或准备后台操作，并人工审查影响范围。
2. 在树莓派主库执行前先备份树莓派数据库。
3. 只对树莓派主库执行写入。
4. 验证 `https://gesp-csp-quiz.randolph87.top/api/health`、学生端和管理端。
5. 抽查关键表或页面，确认数据更新符合预期。
6. 将树莓派最新 dump 恢复到 Fly Postgres，更新冷备恢复点。
7. 验证 Fly 冷备可启动后，再停止 Fly Web 和 Fly Postgres 保持低成本状态。

如果某份历史文档仍写“同步 Fly 远端”或“Fly 远端数据库”，按当前约定理解为“先同步树莓派主库，再同步 Fly 冷备”。需要直接操作 Fly 时，文档或任务必须明确写出“Fly 冷备”。

## 需求拆解

### 1. 从 Fly.io 迁移数据到树莓派 Docker PostgreSQL

- 当前现状：
  - Fly.io 使用 PostgreSQL 保存用户、题目、试卷、答题记录、消息、纠错记录等业务数据。
  - 树莓派 Docker Compose 使用 `postgres:15` 容器和命名卷 `xzs-postgres-data` 持久化数据库。
- 判断：
  - 迁移重点是导出 Fly Postgres，再恢复到树莓派的 `xzs-postgres` 容器。
  - 为避免丢数据，最终导出前必须停止或冻结 Fly 侧写入。
- 修改方案：
  - 先做一次不停服演练迁移，确认 Docker PostgreSQL 可恢复、Java 容器可启动、核心数据可见。
  - 最终迁移时开启短暂停写窗口，停止 Fly Web 写入口，导出最终 dump，恢复到树莓派 Docker PostgreSQL，再把用户入口切到树莓派 URL。
- 影响范围：
  - Docker PostgreSQL 数据卷 `xzs-postgres-data`。
  - 对外访问入口、域名或分享链接。
  - Fly.io 暂停、保留或下线策略。
- 验证方案：
  - 对树莓派 URL 运行 `scripts/test-remote-deployment.ps1`。
  - 登录管理端和学生端，检查最近用户、题目、试卷、答题记录和成绩。
  - 对 Fly 和树莓派分别查询关键表行数，确认恢复后的数量一致。

### 2. 切换后以树莓派为主

- 当前现状：
  - Fly.io 冷启动会影响首次访问体验。
  - 树莓派 Docker 服务常驻运行可避免 Fly Web 和 Fly Postgres 冷启动等待。
- 判断：
  - 主入口只能有一个；切换后必须避免用户继续访问 Fly 旧地址产生新数据。
- 修改方案：
  - 如果有自定义域名，把 DNS 或反向代理上游切到树莓派公网入口。
  - 如果暂时没有域名，就明确公布树莓派 URL，并停止使用 Fly URL。
  - Fly 保留 3 到 7 天作为回滚源；期间不要让用户继续在 Fly 上答题或管理数据。
- 影响范围：
  - 用户书签、二维码、分享链接、管理端入口。
  - HTTPS 证书和反向代理配置。
- 验证方案：
  - 从公网访问树莓派 URL，确认 `/api/health` 返回 `UP` 且数据库状态为 `UP`。
  - 完成一次学生端登录、答题提交、管理端查看记录的端到端检查。

### 3. 后续数据备份

- 当前现状：
  - Docker Compose PostgreSQL 数据保存在命名卷 `xzs-postgres-data`。
  - 备份应优先使用 PostgreSQL 逻辑备份 `pg_dump --format custom`，而不是直接复制 Docker volume。
  - Fly.io 已有低成本冷启动部署，可以作为备用服务节点承接灾难恢复。
- 判断：
  - 只把备份放在树莓派本机不够；SD 卡、硬盘或整机故障会同时带走数据库和备份。
  - 用 Fly 作为冷备是合理选择：平时成本低，故障时可通过冷启动临时恢复访问。
  - Fly 冷备不是实时主从复制；必须通过定期 dump/restore 把树莓派数据覆盖到 Fly。
- 修改方案：
  - 本机每日凌晨通过 `docker exec xzs-postgres pg_dump` 生成 `.dump` 文件，保留 14 到 30 份。
  - 每日凌晨把树莓派最新 `.dump` 恢复到 Fly Postgres，使 Fly URL 成为可启动的备用环境。
  - 重要数据变更前后，例如批量导题、批量改题、应用升级前后，手动额外同步一次 Fly。
  - 每月做一次恢复演练，证明备份文件真的可恢复。
- 影响范围：
  - 树莓派备份目录磁盘占用，例如 `/opt/xzs/backups`。
  - Docker Compose 中数据库密码管理。
  - Fly Postgres 数据会被定期覆盖为树莓派快照。
  - Fly URL 的开放策略和故障切换流程。
- 验证方案：
  - 手动运行一次备份，确认生成 `.dump` 文件。
  - 手动执行一次从树莓派恢复到 Fly，确认 Fly 健康检查和关键页面正常。
  - 在临时数据库或测试 Docker PostgreSQL 中恢复一次。

## 推荐执行顺序

### 0. 准备树莓派 Docker 运行环境

进入树莓派上的项目目录，确认 Docker 服务正常：

```sh
docker compose -f docker/docker-compose.yml ps
APP_CONTAINER=xzs-app
docker logs --tail=100 "$APP_CONTAINER"
curl -fsS http://127.0.0.1:8000/api/health
```

如果你是在 `docker` 目录内执行，也可以使用：

```sh
docker compose ps
docker compose logs --tail=100 java
curl -fsS http://127.0.0.1:8000/api/health
```

建议树莓派运行的 Jar 版本与 Fly 当前版本一致，或至少是兼容同一套数据库 schema 的更新版本。若 Fly 上已有更新 schema，而树莓派 Jar 较旧，可能启动失败或页面异常。

### 1. 获取 Fly 数据库连接信息

如果本地已经保存 Fly 数据库连接串，可直接使用。否则可以在 Fly Web App 运行时读取 `DATABASE_URL`：

```powershell
fly ssh console -a gesp-csp-quiz -C "printenv DATABASE_URL"
```

把输出当作敏感信息处理，不要提交到仓库或聊天记录。后续命令中的 `<fly-db-user>`、`<fly-db-password>`、`xzs_cb867393296` 以实际连接串为准。

### 2. 演练导出 Fly 数据库

在开发机打开一个终端启动 Fly Postgres 代理：

```powershell
fly proxy 15432:5432 -a xzs-pg-cb867393296
```

另开一个终端导出数据库：

```powershell
New-Item -ItemType Directory -Force .\backups
$env:PGPASSWORD = "<fly-db-password>"
pg_dump `
  --host localhost `
  --port 15432 `
  --username "<fly-db-user>" `
  --dbname xzs_cb867393296 `
  --format custom `
  --no-owner `
  --no-privileges `
  --file .\backups\xzs-fly-rehearsal.dump
Remove-Item Env:\PGPASSWORD
```

如果本地没有 `pg_dump`，在开发机安装与 Fly Postgres 主版本相同或更高的 PostgreSQL 客户端工具。

### 3. 演练恢复到树莓派 Docker PostgreSQL

把演练 dump 传到树莓派：

```powershell
scp .\backups\xzs-fly-rehearsal.dump <pi-user>@<pi-host>:/tmp/
```

在树莓派执行恢复。关键点是只停应用容器，保留 PostgreSQL 容器运行。生产环境如果不是 `xzs-app`，先用 `docker ps` 确认后替换 `APP_CONTAINER`：

```sh
APP_CONTAINER=xzs-app
mkdir -p /opt/xzs/backups
sudo install -m 0600 /tmp/xzs-fly-rehearsal.dump /opt/xzs/backups/xzs-fly-rehearsal.dump

docker stop "$APP_CONTAINER"
docker cp /opt/xzs/backups/xzs-fly-rehearsal.dump xzs-postgres:/tmp/xzs-fly-rehearsal.dump
docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres pg_restore \
  --host 127.0.0.1 \
  --port 5432 \
  --username xzs \
  --dbname xzs \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  /tmp/xzs-fly-rehearsal.dump
docker start "$APP_CONTAINER"
```

如果树莓派使用仓库默认密码，`<raspberry-pi-db-password>` 是 `xzs_change_me`；如果你已经改过密码，以树莓派实际 Docker Compose 配置为准。

在开发机验证树莓派 URL：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://<raspberry-pi-url>"
```

没有 HTTPS 时先使用：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "http://<raspberry-pi-host>:8000"
```

再手工检查关键表行数：

```sh
docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres psql \
  --username xzs \
  --dbname xzs \
  --command "select 't_user' as table_name, count(*) from t_user union all select 't_question', count(*) from t_question union all select 't_exam_paper', count(*) from t_exam_paper union all select 't_exam_paper_answer', count(*) from t_exam_paper_answer union all select 't_task_exam', count(*) from t_task_exam;"
```

同样的 SQL 在 Fly 和树莓派各执行一次，行数应一致。若演练恢复后发现树莓派数据不对，不要进入最终切换。

### 4. 最终迁移停写窗口

最终迁移前先通知所有使用者暂停答题和后台管理。推荐选择低使用时段执行。

停止 Fly Web 写入口：

```powershell
fly machine list -a gesp-csp-quiz
fly machine stop <web-machine-id> -a gesp-csp-quiz
```

如果 Fly URL 仍可能被用户访问并自动拉起机器，应同时暂停对 Fly URL 的公开使用；有自定义域名时先准备好切换到树莓派，但不要在最终 dump 完成前开放新写入。

重新导出最终 dump：

```powershell
fly proxy 15432:5432 -a xzs-pg-cb867393296
New-Item -ItemType Directory -Force .\backups
$env:PGPASSWORD = "<fly-db-password>"
pg_dump `
  --host localhost `
  --port 15432 `
  --username "<fly-db-user>" `
  --dbname xzs_cb867393296 `
  --format custom `
  --no-owner `
  --no-privileges `
  --file .\backups\xzs-fly-final.dump
Remove-Item Env:\PGPASSWORD
```

恢复到树莓派 Docker PostgreSQL：

```powershell
scp .\backups\xzs-fly-final.dump <pi-user>@<pi-host>:/tmp/
```

```sh
APP_CONTAINER=xzs-app
mkdir -p /opt/xzs/backups
sudo install -m 0600 /tmp/xzs-fly-final.dump /opt/xzs/backups/xzs-fly-final.dump

docker stop "$APP_CONTAINER"
docker cp /opt/xzs/backups/xzs-fly-final.dump xzs-postgres:/tmp/xzs-fly-final.dump
docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres pg_restore \
  --host 127.0.0.1 \
  --port 5432 \
  --username xzs \
  --dbname xzs \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  /tmp/xzs-fly-final.dump
docker start "$APP_CONTAINER"
```

通过验证后，正式把入口切到树莓派：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://<raspberry-pi-url>"
```

### 5. 切换后的 Fly 冷备策略

切换完成后建议长期保留 Fly Web App 和 Fly Postgres 作为冷备，但不要让用户日常使用 Fly URL。日常只开放树莓派 URL；Fly URL 只用于健康检查、恢复演练和树莓派故障时的临时入口。

推荐策略：

- 树莓派是唯一主写入节点。
- Fly 每日或每 6 小时接收一次树莓派数据库快照。
- Fly Web App 和 Fly Postgres 保持冷启动低成本配置。
- 同步到 Fly 前先停止 Fly Web，避免同步期间有用户写入或应用连接占用。
- 同步完成后运行一次 Fly 冷备检查，确认冷备可用；检查完成后可以再次停止 Fly Web 和 Fly Postgres。

如果树莓派出现严重问题且需要回滚：

1. 停止树莓派写入入口，例如 `APP_CONTAINER=xzs-app; docker stop "$APP_CONTAINER"`。
2. 判断是否能从树莓派导出比 Fly 更新的 dump。
3. 如果可以导出，先把最新 dump 恢复到 Fly，再开放 Fly URL。
4. 如果树莓派完全不可用，只能开放 Fly 上最近一次同步的数据，并接受相应 RPO 数据损失。

不要删除 Fly Postgres；它就是后续的冷备数据库。

## 后续备份方案

### 本机每日备份

推荐先用 cron。备份命令直接调用 PostgreSQL 容器内的 `pg_dump`，输出到树莓派宿主机目录。

创建备份目录并手动跑一次：

```sh
sudo mkdir -p /opt/xzs/backups
sudo chmod 0700 /opt/xzs/backups

timestamp="$(date +%Y%m%d-%H%M%S)"
docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres pg_dump \
  --host 127.0.0.1 \
  --port 5432 \
  --username xzs \
  --dbname xzs \
  --format custom \
  --no-owner \
  --no-privileges \
  > "/opt/xzs/backups/xzs-${timestamp}.dump"
```

编辑 root crontab：

```sh
sudo crontab -e
```

加入每日凌晨 03:15 备份任务。注意把密码替换为树莓派实际数据库密码：

```cron
15 3 * * * mkdir -p /opt/xzs/backups && timestamp="$(date +\%Y\%m\%d-\%H\%M\%S)" && docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres pg_dump --host 127.0.0.1 --port 5432 --username xzs --dbname xzs --format custom --no-owner --no-privileges > "/opt/xzs/backups/xzs-${timestamp}.dump" 2>> /opt/xzs/backups/backup-db.log && find /opt/xzs/backups -maxdepth 1 -type f -name 'xzs-*.dump' -printf '\%T@ \%p\n' | sort -rn | tail -n +31 | cut -d' ' -f2- | xargs -r rm -f
```

如果不想把密码写进 crontab，建议在树莓派上创建 root-only 环境文件，例如 `/etc/xzs/docker-db.env`：

```sh
sudo install -d -m 0700 /etc/xzs
sudo sh -c "printf 'PGPASSWORD=%s\n' '<raspberry-pi-db-password>' > /etc/xzs/docker-db.env"
sudo chmod 0600 /etc/xzs/docker-db.env
```

然后把 cron 改成先读取该文件：

```cron
15 3 * * * . /etc/xzs/docker-db.env; mkdir -p /opt/xzs/backups && timestamp="$(date +\%Y\%m\%d-\%H\%M\%S)" && docker exec -e PGPASSWORD="$PGPASSWORD" xzs-postgres pg_dump --host 127.0.0.1 --port 5432 --username xzs --dbname xzs --format custom --no-owner --no-privileges > "/opt/xzs/backups/xzs-${timestamp}.dump" 2>> /opt/xzs/backups/backup-db.log && find /opt/xzs/backups -maxdepth 1 -type f -name 'xzs-*.dump' -printf '\%T@ \%p\n' | sort -rn | tail -n +31 | cut -d' ' -f2- | xargs -r rm -f
```

### 同步到 Fly 冷备

同步到 Fly 的推荐流程是：先在树莓派生成 dump，再传回开发机或一台运维机，最后通过 `fly proxy` 恢复到 Fly Postgres。恢复 Fly 前应停止 Fly Web，避免同步期间发生写入。

在树莓派生成备份：

```sh
timestamp="$(date +%Y%m%d-%H%M%S)"
docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres pg_dump \
  --host 127.0.0.1 \
  --port 5432 \
  --username xzs \
  --dbname xzs \
  --format custom \
  --no-owner \
  --no-privileges \
  > "/opt/xzs/backups/xzs-to-fly-${timestamp}.dump"
```

把备份拉到开发机或运维机：

```powershell
scp <pi-user>@<pi-host>:/opt/xzs/backups/xzs-to-fly-<timestamp>.dump .\backups\
```

停止 Fly Web 写入口：

```powershell
fly machine list -a gesp-csp-quiz
fly machine stop <web-machine-id> -a gesp-csp-quiz
```

启动 Fly Postgres 代理：

```powershell
fly proxy 15432:5432 -a xzs-pg-cb867393296
```

另开一个终端，把树莓派备份恢复到 Fly Postgres：

```powershell
$env:PGPASSWORD = "<fly-db-password>"
pg_restore `
  --host localhost `
  --port 15432 `
  --username "<fly-db-user>" `
  --dbname xzs_cb867393296 `
  --clean `
  --if-exists `
  --no-owner `
  --no-privileges `
  .\backups\xzs-to-fly-<timestamp>.dump
Remove-Item Env:\PGPASSWORD
```

恢复完成后验证 Fly 冷备：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://gesp-csp-quiz.fly.dev" -RetryCount 45 -RetryDelaySeconds 10
```

如果只是验证冷备可启动，检查完成后可以再次停止 Fly Web 和 Fly Postgres：

```powershell
fly machine list -a gesp-csp-quiz
fly machine stop <web-machine-id> -a gesp-csp-quiz

fly machine list -a xzs-pg-cb867393296
fly machine stop <postgres-machine-id> -a xzs-pg-cb867393296
```

推荐同步频率：

- 普通阶段：每日凌晨同步一次到 Fly，RPO 约 24 小时。
- 有学生集中使用或近期频繁更新题库时：每 6 小时同步一次，RPO 约 6 小时。
- 批量导题、批量改题、升级前后：手动立即同步一次。

### 额外异机备份

Fly 冷备可以作为主要异地备份，但仍建议至少保留最近几份 `.dump` 文件在树莓派或开发机上，避免误操作把错误数据同步到 Fly 后没有更早版本可退。

如果还想再加一层低成本备份，可以同步到另一台 Linux 主机或 NAS：

```sh
rsync -av --ignore-existing /opt/xzs/backups/ <backup-user>@<backup-host>:/srv/backups/xzs/
```

如果备份目标只支持 `scp`：

```sh
scp /opt/xzs/backups/*.dump <backup-user>@<backup-host>:/srv/backups/xzs/
```

推荐保留策略：

- 树莓派本机：最近 30 天每日备份。
- Fly 冷备：保留一份最近可启动数据快照。
- 备份文件：至少保留最近 7 到 30 份 `.dump`，用于误删、错误同步或题库批量操作回滚。
- 每次应用大版本升级、批量导题、批量改题前，手动做一次带说明的备份。

### 恢复演练

每月至少做一次恢复演练。不要直接覆盖生产库，可以在同一个 PostgreSQL 容器里创建临时数据库：

```sh
docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres createdb \
  --host 127.0.0.1 \
  --username xzs \
  xzs_restore_test

docker cp /opt/xzs/backups/<backup-file>.dump xzs-postgres:/tmp/xzs-restore-test.dump

docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres pg_restore \
  --host 127.0.0.1 \
  --port 5432 \
  --username xzs \
  --dbname xzs_restore_test \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  /tmp/xzs-restore-test.dump
```

演练后检查关键表行数，并删除临时库：

```sh
docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres psql \
  --username xzs \
  --dbname xzs_restore_test \
  --command "select count(*) from t_user;"

docker exec -e PGPASSWORD='<raspberry-pi-db-password>' xzs-postgres dropdb \
  --host 127.0.0.1 \
  --username xzs \
  xzs_restore_test
```

## 风险与待确认

- 待确认：树莓派最终公网 URL、是否使用 HTTPS、是否有自定义域名。
- 待确认：Fly 数据库连接串是否可从现有记录或 `fly ssh console` 获取。
- 待确认：树莓派 Docker Compose 中实际数据库密码；不要假设生产仍使用示例密码 `xzs_change_me`。
- 待确认：Fly 冷备同步频率；建议普通阶段每日一次，集中使用阶段每 6 小时一次。
- 风险：最终 dump 导出后，如果仍有人访问 Fly 并写入数据，树莓派不会自动获得这些新增数据。
- 风险：只做树莓派本机备份不能覆盖整机损坏、误删和存储卡故障。
- 风险：把树莓派数据同步到 Fly 是覆盖式恢复；如果树莓派数据已经被误删或污染，直接同步会把错误数据也覆盖到 Fly。
- 风险：Fly 冷备的恢复点取决于最近一次同步时间，不等价于实时高可用。
- 风险：直接复制 Docker volume 不等价于可验证的数据库备份；日常备份应使用 `pg_dump --format custom`。
- 风险：如果树莓派 Jar 版本落后于 Fly 数据库 schema，恢复成功后应用也可能启动失败。
