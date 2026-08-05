# Docker Compose 生产部署

本目录保存树莓派生产环境的 Docker Compose 配置。当前环境约定固定为：

- 树莓派是生产环境，应用连接同一 Compose 项目中的本地 PostgreSQL 18。
- Fly.io 是测试环境，连接 Neon `test` branch。
- 本地是开发环境，连接 Neon `test` branch。

树莓派本地 PostgreSQL 是唯一生产主写入库，数据必须绑定到 USB SSD 的显式路径。
Compose 不映射宿主机 `5432`。极空间 `/mnt/zspace-xzs-backup` 只保存备份文件，
不保存实时数据目录。本说明假设该挂载已经稳定可写，不修改 NAS 挂载、权限、容量或快照设置。
应用仍以包含后端 Jar、管理端和学生端静态资源的完整镜像运行。

树莓派和 Fly 测试环境共用同一个根目录 `Dockerfile`。公共镜像构建、运行参数和环境差异见 `docs/container-image-deployment.md`。

## 镜像

默认镜像：

```text
crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:latest
```

推荐每次发布同时推送两个 tag：

- `latest`：树莓派默认更新目标。
- Git 短提交号，例如 `aa08063f`：用于精确回滚。

2026-07-27 正式切换使用并固定的 ARM64 应用镜像 tag 是 `986c8aa4`。正式切换、
恢复和回滚必须使用该类明确 tag 或不可变 digest，不能使用 `latest`。同一
`Dockerfile` 构建的 Fly release v15 已在 Neon `test` 环境通过测试。

本地构建并推送 `linux/arm64` 镜像：

```powershell
docker buildx build --platform linux/arm64 `
  -t crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:<git-sha> `
  -t crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:latest `
  -f Dockerfile `
  --push .
```

## 树莓派首次部署

在树莓派上准备应用目录：

```sh
sudo mkdir -p /opt/apps/gesp-csp-quiz
sudo chown -R "$USER:$USER" /opt/apps/gesp-csp-quiz
cd /opt/apps/gesp-csp-quiz
```

复制仓库中的两个文件到 `/opt/apps/gesp-csp-quiz`：

```text
docker-compose.yml
.env.production.example
```

把模板复制为真实环境文件：

```sh
cp .env.production.example .env
chmod 600 .env
```

编辑 `.env`：

```sh
nano .env
```

必须替换：

- `XZS_POSTGRES_PASSWORD`：本地 PostgreSQL 强密码。
- `XZS_POSTGRES_DATA_DIR`：已确认位于 USB SSD 的数据目录，例如
  `<USB-SSD>/xzs/postgres/data`。不能使用 SD 卡路径或 NAS 路径。
- `XZS_BACKUP_STAGING_DIR`：USB SSD 上独立的备份暂存目录。
- `XZS_AI_CONFIG_SECRET`：生产环境固定密钥，32 字符或更长。该值用于加密/解密老师保存的大模型 API Key，换值后旧密文需要重新保存。

不要把 `.env` 提交到 Git，也不要发到聊天记录或日志里。

首次创建 PostgreSQL bind 目录后，必须让容器内 PostgreSQL 用户拥有该目录：

```sh
sudo chown -R 999:999 "<XZS_POSTGRES_DATA_DIR>"
```

只对已经确认的 PostgreSQL 专用 bind 目录执行该命令，不要对 USB SSD 挂载根目录、
应用目录或 NAS 目录递归改属主。

也可以固定使用“本地填写、脚本复制”的方式：在开发机把模板复制为 `docker/.env.production`，填好生产配置后执行：

```powershell
.\scripts\sync-raspi-production-env.ps1
```

脚本会把本地 `docker/.env.production`、Compose、`.env.shadow.example` 和
`deploy/raspberry-pi/docker` 运维资产复制到树莓派，备份远端旧文件，并只做
Compose 配置校验。同步本身不会安装 systemd unit。确认要同步配置并切换容器时执行：

```powershell
.\scripts\sync-raspi-production-env.ps1 -Restart
```

只准备影子演练资产时必须使用专用模式：

```powershell
.\scripts\sync-raspi-production-env.ps1 -ShadowAssetsOnly
```

该模式不读取、转换、上传、备份或替换生产 `.env`，只备份式同步 Compose、
`.env.shadow.example` 和 `ops`，随后用无 secret 的临时占位配置检查生产默认形态和
影子形态均可展开。它不会启动容器，也不能与 `-Restart`、`-SkipPull`、`-Verify`
或 `-AllowPlaceholders` 组合。

Neon production 刷新和后续 `test` reset 不使用上述应用 `.env`。先从专用模板创建
本地忽略文件并离线查看部署计划；计划模式不读取任何 secret，也不连接远端：

```powershell
Copy-Item docker/.env.neon-production-refresh.example docker/.env.neon-production-refresh
# 填写真实值后再继续；不要打印或提交该文件。
.\scripts\deploy-raspi-neon-refresh.ps1 -Plan
```

默认执行只上传所需 ops 脚本和三个 systemd unit（人工 service、日常 service、timer），把专用配置原子安装为
`/etc/xzs/neon-production-refresh.env`（`root:root 0600`），执行 Bash/Python、unit、
命令依赖和文件权限的离线预检，并主动保持 timer 禁用。它不会运行刷新或 reset：

```powershell
.\scripts\deploy-raspi-neon-refresh.ps1
```

该入口复用 `sync-raspi-production-env.ps1` 的 Cloudflare TCP 隧道、根目录 `.env`
中的 `MY_SSH_KEY` 和 Paramiko 认证方式；密码与 Neon secret 都通过标准输入或 SFTP
传输，不进入命令行和日志。应用日常同步仍可独立使用原入口，两个脚本写入同一个
`/opt/apps/gesp-csp-quiz/ops`，但专用入口只覆盖刷新所需白名单文件。

登录阿里云 ACR：

```sh
sudo docker login --username=randolph87 crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com
```

启动：

```sh
docker compose pull
docker compose up -d
docker compose ps
docker logs --tail=100 xzs-app
```

`docker compose ps` 必须显示 `xzs-postgres` 健康、`xzs-app` 运行。Compose 文件没有
PostgreSQL `ports` 配置，因此宿主机和公网不应能直接访问 `5432`。

## 影子 PostgreSQL 与应用验收

影子环境复用 `docker-compose.yml`，但始终使用固定项目名 `xzs-shadow` 和独立
`.env.shadow`。生产默认仍是 `xzs-postgres`、`xzs-app` 和
`0.0.0.0:8000`；影子环境固定使用 `xzs-postgres-shadow`、
`xzs-app-shadow` 和 `127.0.0.1:18000`。两个 Compose project 的默认网络互相独立，
PostgreSQL 均不映射宿主机端口。

准备真实影子配置：

```sh
cd /opt/apps/gesp-csp-quiz
cp .env.shadow.example .env.shadow
chmod 600 .env.shadow
nano .env.shadow
```

必须把 `XZS_POSTGRES_DATA_DIR` 替换为 USB SSD 上与生产完全不同、且路径组件明确包含
`shadow` 的目录。影子数据库密码和 AI 配置密钥只写入被忽略的 `.env.shadow`。

从指定备份完整准备影子环境：

```sh
./ops/prepare-shadow-environment.sh \
  --backup /mnt/zspace-xzs-backup/gesp-csp-quiz/hourly/xzs-<timestamp>.dump
```

脚本按固定顺序执行：

1. 断言影子项目、容器名、回环端口和数据目录不会与生产冲突。
2. 验证 custom archive、`.sha256` 和 manifest。
3. 只启动 `xzs-shadow` 项目的 PostgreSQL。
4. 重建影子目标库并完整恢复。
5. 启动当前应用镜像，通过启动时 Flyway 和 JDBC 验证。
6. 等待 `http://127.0.0.1:18000/api/health` 成功。

影子入口只绑定回环地址。需要从开发机查看时，应使用 SSH 端口转发，不要改成公网绑定。

默认清理只删除影子容器和影子网络，保留影子数据：

```sh
./ops/cleanup-shadow-environment.sh
```

删除影子数据目录是不可恢复操作，必须同时使用参数和精确确认变量：

```sh
XZS_SHADOW_DELETE_CONFIRM=DELETE_XZS_SHADOW_DATA \
  ./ops/cleanup-shadow-environment.sh --delete-data
```

脚本会再次确认目录是绝对路径、包含 shadow 专用组件、不同于生产数据目录，且不位于
应用目录或 NAS 备份树内。

2026-07-27 的真实环境演练已验证：

- Neon production custom dump 可恢复到树莓派影子 PostgreSQL 18；Neon 特有的
  `pg_session_jwt` 扩展和注释通过严格白名单 TOC 过滤跳过，其余 TOC 项不放宽。
- 影子应用的功能检查和 5 轮 API 测量通过。
- 真实极空间上的影子备份发布及隔离恢复通过。
- 5 轮 API 记录值如下，单位为毫秒：

| 场景 | 树莓派 + Neon 基线 | 影子本地 PostgreSQL |
| --- | ---: | ---: |
| `current` | 2950.6 | 1595.6 |
| `wrong` | 3886.8 | 2337.8 |
| `workspace` | 2834.7 | 1651.6 |
| `records` | 2819.5 | 2105.8 |

以上是影子环境数据；最终公网生产结果见正式切换记录。

## Neon 到本地 PostgreSQL 正式切换

正式入口是 `ops/cutover-neon-to-local-postgres.sh`。切换前先确认 NAS 挂载可写、
目标数据目录为空、固定应用镜像和 PostgreSQL 镜像已拉取，并且生产应用仍健康。
先执行只读预检：

```sh
cd /opt/apps/gesp-csp-quiz
sudo ./ops/cutover-neon-to-local-postgres.sh \
  --image crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:986c8aa4 \
  --data-dir "<USB-SSD>/xzs" \
  --confirm CUTOVER_NEON_TO_LOCAL \
  --dry-run
```

预检通过后，去掉 `--dry-run` 执行正式切换。只有已经确认根文件系统本身位于
`/dev/sd*` 或 `/dev/nvme*` USB SSD、且不是 SD/MMC 时，才追加
`--allow-root-usb-ssd`；普通独立挂载不需要该参数。

脚本要求固定 tag/digest 和 `--confirm CUTOVER_NEON_TO_LOCAL`，并在内部调用正式恢复
入口的生产库双确认门。它会停止旧应用、生成并校验最终 Neon dump、恢复本地
PostgreSQL、验证应用、生成首份小时备份、执行隔离恢复测试，再启用备份与恢复演练
timer。任何切换阶段失败都会恢复旧 Neon 环境并重启回滚容器。

2026-07-27 已完成正式切换：

- 生产应用已改为 Compose 内 PostgreSQL 18，固定应用镜像为 `986c8aa4`。
- 首份小时备份为 `xzs-20260727T090616Z.dump`，对应隔离恢复报告为
  `restore-test-20260727T090623Z-26482.json`，均已通过。
- `xzs-postgres-backup.timer` 和 `xzs-postgres-restore-test.timer` 已启用；
  `xzs-neon-dr-refresh.timer` 在 7 天稳定观察完成前保持未启用。
- 旧 Neon 环境备份及独立的停止态 `xzs-app-neon-rollback` 容器继续保留，观察期内
  不删除。
- 最终健康检查为 `UP`，`xzs-app` 与 `xzs-postgres` 的 restart count 均为 `0`；
  两个本地备份/恢复 timer 为 active，Neon DR timer 为 inactive。
- 树莓派温度为 39.9°C，未发生降频。

最终公网生产每项 5 次测量如下：

| 场景 | 中位数（ms） | P95（ms） | 相对树莓派 + Neon 基线 |
| --- | ---: | ---: | ---: |
| `current` | 742.9 | 1968.0 | 快 2207.7 ms / 74.8% |
| `wrong` | 1090.1 | 1860.4 | 快 2796.7 ms / 72.0% |
| `workspace` | 729.0 | 1642.4 | 快 2105.7 ms / 74.3% |
| `records` | 748.7 | 1410.8 | 快 2070.8 ms / 73.4% |

Playwright 已通过首页、错题本翻页和考试记录只读流程，未产生写入；控制台为
`0 errors`、`1` 条未分类 warning。核心上线验收结论为 **PASS**，但该 warning
仍需分类，计划继续保持 active 至 7 天稳定观察结束。

排查期间 Neon 凭据曾出现在诊断输出中。生产稳定后必须轮换 Neon production 密码，
并把新凭据只同步到未来专用 DR 配置；不要在命令、日志、文档或聊天中记录连接串或密码。

验证：

```sh
curl -fsS http://127.0.0.1:8000/api/health
curl -I http://127.0.0.1:8000/student/index.html
curl -I http://127.0.0.1:8000/admin/index.html
```

公网域名接在反向代理或 Cloudflare 后时，再从开发机验证：

```powershell
.\scripts\test-deployment-acceptance.ps1 -Target Raspi
```

## 日常更新

在开发机推送新镜像并完成本地、Fly 两级验收后，先离线查看将执行的非敏感发布
命令；该模式不读取 `.env`、SSH 密码，也不连接树莓派：

```powershell
.\scripts\sync-raspi-production-env.ps1 -RenderRestartPlan -Verify
```

生产发布需要单独明确确认。确认后从开发机执行标准入口：

```powershell
.\scripts\sync-raspi-production-env.ps1 -Restart -Verify
```

日常发布只执行 `docker compose pull app` 和
`docker compose up -d --no-deps app`。脚本在更新前后分别读取 Compose `postgres`
服务的容器 ID 与 Docker `RestartCount`；容器缺失、身份改变或重启计数变化时硬性
失败。它不会为日常应用发布执行全栈 `up`，也不会联动重建或重启 PostgreSQL。
`-SkipPull` 只跳过 `app` 镜像拉取，`-Verify` 只追加健康与公共页面检查；
不带 `-Restart` 时仍只同步、备份并校验配置，不更新容器。

## 树莓派 SSH 登录约定

树莓派的固定 SSH 入口如下：

```text
SSH 别名：my-rp
主机：rp.randolph87.top
用户：caobin
生产应用目录：/opt/apps/gesp-csp-quiz
```

本机 `~/.ssh/config` 使用 Cloudflare Access：

```sshconfig
Host my-rp
    HostName rp.randolph87.top
    User caobin
    ProxyCommand cloudflared access ssh --hostname %h
```

人工登录可以执行：

```powershell
ssh my-rp
```

当前远端仍需要密码认证，因此自动化任务不要使用 `ssh -o BatchMode=yes my-rp`，该方式会直接报 `Permission denied`。项目的标准自动部署入口是：

```powershell
.\scripts\sync-raspi-production-env.ps1 -Restart -Verify
```

该脚本会：

1. 从被 Git 忽略的根目录 `.env` 读取 `MY_SSH_KEY`。
2. 使用 `cloudflared access tcp --hostname rp.randolph87.top --url localhost:<临时端口>` 建立本地隧道。
3. 使用 Paramiko 以 `caobin` 用户连接本地隧道。
4. 备份远端 `.env` 和 `docker-compose.yml`，校验 compose，按参数拉取、更新并验证容器。

密码不得写入命令行参数、临时脚本、提交文件或聊天日志。只读自动排查也应复用相同的 Cloudflare TCP 隧道与 Paramiko 连接方式。

如果要固定部署某个版本，把 `.env` 里的 `XZS_IMAGE` 改成具体 tag，例如：

```text
XZS_IMAGE=crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:aa08063f
```

再执行：

```powershell
.\scripts\sync-raspi-production-env.ps1 -Restart -Verify
```

## 回滚

把本地生产配置中的 `XZS_IMAGE` 改回上一版已知正常的 Git 短提交 tag，然后仍通过
带 PostgreSQL 前后保护的 app-only 标准入口重新拉取、启动和验证：

```powershell
.\scripts\sync-raspi-production-env.ps1 -Restart -Verify
```

如果应用启动失败，先查看：

```sh
docker compose ps
docker logs --tail=200 xzs-app
```

## 资源参数

默认 compose 针对树莓派做了保守配置：

```text
JAVA_TOOL_OPTIONS=-Xms128m -Xmx512m -XX:+UseSerialGC
SERVER_UNDERTOW_IO_THREADS=2
SERVER_UNDERTOW_WORKER_THREADS=16
SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE=4
SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE=1
```

如果内存吃紧，可先把 `JAVA_TOOL_OPTIONS` 中的 `-Xmx512m` 降到 `-Xmx384m`。调整前后都检查：

```sh
docker stats xzs-app
free -h
df -h
```

## 数据库与备份

树莓派 Compose 内的 PostgreSQL 18 是生产主库；应用通过 Docker 内部
`postgres:5432` 访问。Fly 和本地开发继续使用 Neon test，不读取本文件的 Compose。

Docker 路线运维资产位于 `deploy/raspberry-pi/docker`：

- `backup-postgres-to-zspace.sh`：用 `flock` 防重叠，在 USB SSD 暂存 custom dump，
  完成 `pg_restore --list`、SHA-256 和 manifest 后，以 `.partial` 复制到
  `/mnt/zspace-xzs-backup/gesp-csp-quiz`，校验通过才原子改名并更新 `latest.json`。
- `verify-postgres-backup.sh`：校验 archive、SHA-256 和 manifest。
- `test-restore-postgres-backup.sh`：恢复到临时 PostgreSQL 容器，校验 Flyway、
  关键表行数和孤立记录，报告写入 `restore-tests/`，不会接触生产库。
- `restore-postgres-backup.sh`：破坏性恢复入口。必须指定备份和目标库；生产库还要求
  应用已停止、已生成并校验抢救备份，以及专用确认变量。
- `refresh-neon-disaster-recovery.sh`：只刷新专用 Neon DR direct 目标，并要求显式确认。

备份保留范围严格限制在项目根目录的 `hourly`、`daily`、`weekly`、`monthly`
子目录；手动带标签的备份进入 `manual`，不参与自动清理。本地只保留最新 48 个
staging 备份族。小时备份保留 7 天、每日 30 天、每周 12 周、每月 12 个月。

安装定时器模板：

这些 oneshot 服务固定以 `root` 运行，以便使用 Docker socket，并由部署方保证已存在的
`/mnt/zspace-xzs-backup` 对备份服务可写。脚本仍只在
`/mnt/zspace-xzs-backup/gesp-csp-quiz` 项目目录内发布和清理文件；本项目不修改 NAS
挂载、权限或其他配置。

```sh
cd /opt/apps/gesp-csp-quiz
sudo install -m 0644 ops/xzs-postgres-backup.service ops/xzs-postgres-backup.timer /etc/systemd/system/
sudo install -m 0644 ops/xzs-postgres-restore-test.service ops/xzs-postgres-restore-test.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now xzs-postgres-backup.timer xzs-postgres-restore-test.timer
systemctl list-timers 'xzs-postgres-*'
```

备份在每小时第 15 分钟后随机延迟 0–5 分钟执行；隔离恢复每周执行。先手动验证：

```sh
sudo systemctl start xzs-postgres-backup.service
sudo journalctl -u xzs-postgres-backup.service -n 100 --no-pager
sudo systemctl start xzs-postgres-restore-test.service
```

需要手动标记恢复点时，先从 `.env` 取得非 secret 的两个路径变量，再执行：

```sh
XZS_BACKUP_STAGING_DIR="<USB-SSD>/xzs/backup-staging" \
XZS_BACKUP_ROOT="/mnt/zspace-xzs-backup/gesp-csp-quiz" \
./ops/backup-postgres-to-zspace.sh --label before-upgrade
```

Neon 每日刷新分三次显式调用，不能合并越过检查点。第一步只安装和离线预检，timer
保持禁用；第二步才允许首次人工执行 Neon production 刷新和 `test` reset，完成后仍
保持禁用。`-RunOnce` 启动独立的 `xzs-neon-dr-refresh-manual.service`：第一个
`ExecStart` 成功刷新 production 后，第二个 `ExecStart` 才以 `--preserve-current`
保留 reset 前的 test 回滚分支。任一步失败都会停止，不进入下一步：

```powershell
.\scripts\deploy-raspi-neon-refresh.ps1
.\scripts\deploy-raspi-neon-refresh.ps1 `
  -RunOnce `
  -ConfirmManualRun REFRESH_NEON_PRODUCTION_AND_RESET_TEST
```

人工周期必须对账通过，且至少 7 天稳定观察完成后，才能单独启用 timer。启用入口会
再次检查 production 刷新和 test reset 的成功状态属于同一备份代次：

```powershell
.\scripts\deploy-raspi-neon-refresh.ps1 `
  -EnableTimer `
  -ConfirmEnableTimer ENABLE_DAILY_NEON_PRODUCTION_REFRESH_AND_TEST_RESET `
  -ConfirmSevenDayObservationCompleted
```

启用操作只有在 `systemctl enable --now` 成功且 timer 同时为 `enabled`、`active` 后才
提交；任一步失败都会立即执行 `disable --now` 回滚，失败返回时 timer 必须保持禁用。

不传 `-RunOnce` 或 `-EnableTimer` 时绝不执行外部数据库写入；每次普通安装还会主动
禁用 timer，避免重新部署配置时意外触发旧计划。任何安装、预检、人工周期或状态
检查失败都会返回非零退出码，不继续启用 timer。日常
`xzs-neon-dr-refresh.service` 的 test reset 不带 `--preserve-current`，避免每天积累
旧分支；保留回滚分支只用于上述首次人工演练。

不要把生产应用指向 Neon DR；故障切换必须先冻结本地写入，避免双主。Fly.io 固定
为 Neon test 测试环境，不是生产灾备写入目标。
