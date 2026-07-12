# Fly 到树莓派数据迁移方案

## 结论

当前 Fly 上的数据最新，因此迁移时应把 Fly Postgres 作为唯一数据源，树莓派只做一次完整恢复。切换完成后，必须只保留一个写入主库：要么继续在 Fly 上更新解析，要么切到树莓派后只在树莓派写入，不要两边同时改数据。

推荐流程：

1. 在 Fly 上完成当前解析更新，或安排一个短暂停写窗口。
2. 从 Fly Postgres 导出一致性备份。
3. 在树莓派上重建一个干净 PostgreSQL 数据目录。
4. 把备份恢复到树莓派 PostgreSQL。
5. 启动应用，核对关键表数量和 Flyway 迁移记录。
6. 切换入口到树莓派后，把 Fly 应用停掉或改成只读备用。

## 当前环境

- Fly Web App：`gesp-csp-quiz`
- Fly Postgres App：`xzs-pg-cb867393296`
- Fly 业务库：`xzs_cb867393296`
- 树莓派应用目录：`/opt/apps/xzs`
- 树莓派 PostgreSQL 容器：`xzs-postgres`
- 树莓派应用容器：`xzs-app`

Fly 官方当前仍支持通过 `fly postgres connect` 进入 Postgres 控制台，也支持用 `fly proxy` 把远端 Postgres 端口转发到本机。例如官方文档给出的形式是 `fly postgres connect -a <postgres-app-name>` 和 `fly proxy 15432:5432 -a <postgres-app-name>`。

## 迁移前停写

如果你还在 Fly 上更新题目解析，先不要迁移最终数据。可以先演练一次恢复，但最终切换前必须再导出一次最新备份。

正式迁移前建议停写：

```powershell
fly scale count 0 -a gesp-csp-quiz --yes
```

如果你希望迁移过程中仍能打开 Fly 页面查看，可以不立刻停 Web App，但要确保没有人在后台继续编辑题目、解析、用户、试卷和答卷数据。

## 1. 在 Fly 上创建只读导出账号

本机执行：

```powershell
fly postgres connect -a xzs-pg-cb867393296 -d xzs_cb867393296
```

进入 `psql` 后执行，密码换成一个临时强密码：

```sql
create role xzs_migrate login password 'replace-with-a-temporary-strong-password';
grant connect on database xzs_cb867393296 to xzs_migrate;
grant usage on schema public to xzs_migrate;
grant select on all tables in schema public to xzs_migrate;
grant usage, select on all sequences in schema public to xzs_migrate;
```

确认 Flyway 迁移记录存在：

```sql
select installed_rank, version, description, success
from flyway_schema_history
order by installed_rank;
```

这里应该能看到 `1`、`2`、`3` 三个已成功迁移记录。恢复到树莓派时会一起带过去，应用启动后就不会再重复执行 `V2__add_user_target_subject.sql` 和 `V3__add_user_nick_name.sql`。

## 2. 从 Fly 导出备份

本机开第一个 PowerShell 窗口，保持不要关闭：

```powershell
fly proxy 15432:5432 -a xzs-pg-cb867393296
```

本机开第二个 PowerShell 窗口，在项目根目录执行：

```powershell
New-Item -ItemType Directory -Force -Path .\backups
$DumpFile = ".\backups\xzs-fly-$(Get-Date -Format yyyyMMdd-HHmmss).dump"
$env:PGPASSWORD = "replace-with-a-temporary-strong-password"
pg_dump `
  --host localhost `
  --port 15432 `
  --username xzs_migrate `
  --dbname xzs_cb867393296 `
  --format custom `
  --no-owner `
  --no-privileges `
  --file $DumpFile
Remove-Item Env:\PGPASSWORD
$DumpFile
```

导出后做一次本地文件检查：

```powershell
Get-Item $DumpFile
pg_restore --list $DumpFile | Select-String "flyway_schema_history|t_question|t_text_content"
```

## 3. 传到树莓派

```powershell
scp $DumpFile pi@<raspberry-pi-ip>:/opt/apps/xzs/backups/
```

如果你的树莓派用户名不是 `pi`，替换为实际 SSH 用户。

## 4. 在树莓派准备干净数据库

如果树莓派已经按旧方案启动过，并且 PostgreSQL 数据目录里已经混入 `sql/xzs-postgresql.sql` 初始化出的数据，建议重建数据库目录。先保留一份旧目录，避免误删：

```bash
cd /opt/apps/xzs
docker compose down
mv data/postgres "data/postgres.before-fly-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p data/postgres backups logs/app
chmod 700 data/postgres backups
docker compose up -d postgres
docker compose ps
```

确认 `docker-compose.yml` 里没有下面这种挂载：

```yaml
- ./init/01-xzs-postgresql.sql:/docker-entrypoint-initdb.d/01-xzs-postgresql.sql:ro
```

这类初始化 SQL 不能和应用内置 Flyway 迁移混用。

## 5. 在树莓派恢复 Fly 备份

树莓派上执行：

```bash
cd /opt/apps/xzs
set -a
. ./.env
set +a
cat backups/<xzs-fly-dump-file>.dump | docker exec -i \
  -e PGPASSWORD="$POSTGRES_PASSWORD" \
  xzs-postgres \
  pg_restore \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges
```

如果是刚新建的空库，`--clean --if-exists` 出现少量“不存在，跳过”的提示属于正常现象；真正需要关注的是命令最终退出码是否为 `0`。

## 6. 启动应用并验收

树莓派上执行：

```bash
cd /opt/apps/xzs
docker compose up -d app
docker logs --tail=120 xzs-app
curl -f http://127.0.0.1:8000/actuator/health
```

检查关键表数量：

```bash
cd /opt/apps/xzs
set -a
. ./.env
set +a
docker exec -it \
  -e PGPASSWORD="$POSTGRES_PASSWORD" \
  xzs-postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

进入 `psql` 后执行：

```sql
select count(*) as question_count from t_question;
select count(*) as text_content_count from t_text_content;
select count(*) as subject_count from t_subject;
select count(*) as user_count from t_user;
select installed_rank, version, description, success
from flyway_schema_history
order by installed_rank;
```

如果应用日志没有 Flyway 报错，健康检查成功，关键表数量和 Fly 导出前一致，就可以认为数据迁移完成。

## 7. 切换后怎么存数据

### 推荐主线：树莓派作为唯一写入主库

切换到树莓派后，账号、题目、解析、试卷、答卷、成绩等业务数据都存 PostgreSQL，也就是 `/opt/apps/xzs/data/postgres`。代码和前端静态资源不在数据库里，后续通过 Docker 镜像升级。

此时 Fly 最好做两件事之一：

- 停掉 Fly Web App，避免继续写入旧库。
- 保留 Fly 作为临时回退环境，但不要再登录后台编辑数据。

不要采用“双写”或“有时写 Fly、有时写树莓派”的方式，否则题目解析和用户答题记录很快会分叉，后续合并成本很高。

### 32G TF 卡的现实建议

树莓派 4B 8GB 跑这个项目性能够用，但 32G TF 卡不适合作为长期 PostgreSQL 主存储。PostgreSQL 会持续写 WAL、索引和表数据，TF 卡容量和写入寿命都是风险点。

更稳的做法：

- 系统和 Docker 可以继续放 TF 卡。
- PostgreSQL 数据目录迁到 USB 3.0 SSD。
- 备份目录也放 SSD，并定期同步到另一台电脑、NAS 或云盘。

推荐挂载结构：

```text
/mnt/xzs-data/
  postgres/
  backups/
```

对应 compose 只需要把 PostgreSQL 卷改成：

```yaml
volumes:
  - /mnt/xzs-data/postgres:/var/lib/postgresql/data
```

## 8. 备份策略

至少保留三类备份：

1. 迁移前：Fly 导出的 `xzs-fly-*.dump` 不要马上删。
2. 日常：树莓派每天凌晨导出一次 PostgreSQL。
3. 异地：每天或每周把备份同步到树莓派之外的位置。

树莓派每日备份命令示例：

```bash
cd /opt/apps/xzs
set -a
. ./.env
set +a
mkdir -p backups
docker exec \
  -e PGPASSWORD="$POSTGRES_PASSWORD" \
  xzs-postgres \
  pg_dump \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --format custom \
    --no-owner \
    --no-privileges \
  > "backups/xzs-$(date +%Y%m%d-%H%M%S).dump"
find backups -name "xzs-*.dump" -mtime +7 -delete
```

如果还没换 SSD，32G TF 卡上建议只保留最近 3 到 7 份本地备份，并尽快同步到电脑或 NAS。

## 9. 后续更新规则

- 业务数据：只通过 PostgreSQL 保存和备份，不再依赖 `sql/xzs-postgresql.sql`。
- 表结构：只通过 `source/xzs/src/main/resources/db/migration` 下的 Flyway 脚本演进。
- 应用版本：通过 Docker 镜像标签升级和回滚。
- 发布前：先做一次 `pg_dump`。
- 发布后：看 `docker logs --tail=120 xzs-app`，确认没有 Flyway、数据库连接或启动错误。
