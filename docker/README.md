# Docker Compose 生产部署

本目录保存树莓派生产环境的 Docker Compose 配置。当前环境约定固定为：

- 树莓派是生产环境，连接 Neon `production` branch。
- Fly.io 是测试环境，连接 Neon `test` branch。
- 本地是开发环境，连接 Neon `test` branch。

树莓派生产环境不再通过 compose 启动本地 PostgreSQL，也不再挂载本地 jar。应用以完整 Docker 镜像运行，镜像内已经包含后端 Jar、管理端和学生端静态资源。

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

- `SPRING_DATASOURCE_URL`：Neon `production` branch 原始连接串。
- `XZS_AI_CONFIG_SECRET`：生产环境固定密钥，32 字符或更长。该值用于加密/解密老师保存的大模型 API Key，换值后旧密文需要重新保存。

不要把 `.env` 提交到 Git，也不要发到聊天记录或日志里。

也可以固定使用“本地填写、脚本复制”的方式：在开发机把模板复制为 `docker/.env.production`，填好生产配置后执行：

```powershell
.\scripts\sync-raspi-production-env.ps1
```

脚本会把本地 `docker/.env.production` 复制到树莓派 `/opt/apps/gesp-csp-quiz/.env`，备份远端旧 `.env`，并只做 compose 配置校验。确认要同步配置并切换容器时执行：

```powershell
.\scripts\sync-raspi-production-env.ps1 -Restart
```

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

生产数据库在 Neon `production` branch。树莓派 compose 不启动本地 PostgreSQL，生产备份应围绕 Neon production 制定。旧的本地 Docker PostgreSQL 迁移流程只作为历史参考，不再作为当前生产默认方案。

Fly.io 现在固定为测试环境，不作为生产冷备写入目标，不要把生产数据 dump 恢复到 Fly Postgres。
