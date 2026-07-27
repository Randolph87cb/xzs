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
- `NEON_DR_DIRECT_URL`：专用 Neon 灾备目标的 direct（非 pooled）连接串。
- `XZS_AI_CONFIG_SECRET`：生产环境固定密钥，32 字符或更长。该值用于加密/解密老师保存的大模型 API Key，换值后旧密文需要重新保存。

不要把 `.env` 提交到 Git，也不要发到聊天记录或日志里。

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

验证：

```sh
curl -fsS http://127.0.0.1:8000/api/health
curl -I http://127.0.0.1:8000/student/index.html
curl -I http://127.0.0.1:8000/admin/index.html
```

公网域名接在反向代理或 Cloudflare 后时，再从开发机验证：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "https://gesp-csp-quiz.randolph87.top"
```

## 日常更新

在开发机推送新镜像后，树莓派执行：

```sh
cd /opt/apps/gesp-csp-quiz
docker compose pull
docker compose up -d
docker image prune -f
docker logs --tail=100 xzs-app
```

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

```sh
docker compose pull
docker compose up -d
```

## 回滚

把 `.env` 中的 `XZS_IMAGE` 改回上一版 Git 短提交 tag，然后重新拉取启动：

```sh
cd /opt/apps/gesp-csp-quiz
docker compose pull
docker compose up -d
docker logs --tail=100 xzs-app
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

Neon 每日刷新 timer 只在本地主库稳定观察至少 7 天、专用 DR 目标已准备、
首次人工恢复和校验通过后安装并启用：

```sh
sudo install -m 0644 ops/xzs-neon-dr-refresh.service ops/xzs-neon-dr-refresh.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now xzs-neon-dr-refresh.timer
```

不要把生产应用指向 Neon DR；故障切换必须先冻结本地写入，避免双主。Fly.io 固定
为 Neon test 测试环境，不是生产灾备写入目标。
