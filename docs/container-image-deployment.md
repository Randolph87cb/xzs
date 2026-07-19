# 容器镜像部署公共说明

本文统一说明树莓派生产环境和 Fly 测试环境共用的容器镜像、运行参数和部署边界。

## 环境边界

| 环境 | 编排方式 | 镜像来源 | 数据库 |
| --- | --- | --- | --- |
| 树莓派生产 | `docker compose` | 阿里云 ACR `randolph87/gesp-csp-quiz` | Neon `production` branch |
| Fly 测试 | `fly.toml` / `flyctl deploy` | Fly registry，构建自同一个 `Dockerfile` | Neon `test` branch |
| 本地开发 | `scripts/start-local-neon.ps1` 或本地 Java | 本地构建产物 | Neon `test` branch |

树莓派和 Fly 共用根目录 `Dockerfile`。这个 Dockerfile 会先构建管理端和学生端 Vite 产物，再打包 Spring Boot Jar，最终运行同一个 `/app/xzs.jar`。

## 公共镜像构建

生产镜像使用 `linux/arm64`，推送到阿里云 ACR：

```powershell
$tag = git rev-parse --short HEAD
docker buildx build --platform linux/arm64 `
  -t "crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:$tag" `
  -t "crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:latest" `
  -f Dockerfile `
  --push .
```

Fly 测试环境也使用同一个 `Dockerfile`，但由 `flyctl deploy` 构建并推送到 Fly 自己的 registry：

```powershell
.\scripts\deploy-fly-neon-test.ps1
```

## 公共运行参数

以下变量在 Fly 和树莓派都使用相同语义：

- `SPRING_PROFILES_ACTIVE=prod`：运行打包后的生产形态配置。
- `SERVER_PORT=8000`：容器内部监听端口。
- `SPRING_DATASOURCE_URL`：Neon 原始 URL，运行时自动转换为 JDBC URL。
- `SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE`：连接池最大连接数。
- `SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE`：连接池最小空闲连接数。
- `XZS_AI_CONFIG_SECRET`：AI 配置 API Key 加密密钥，必须长期稳定。
- `XZS_LOG_PATH`：容器内日志目录。

不要在可提交文件中写入真实 `SPRING_DATASOURCE_URL`、数据库密码或 `XZS_AI_CONFIG_SECRET`。

## 模板入口

- Fly 测试环境从 `.env.neon-test` 读取测试 secret，部署入口为 `scripts/deploy-fly-neon-test.ps1`。
- 树莓派生产环境从 `/opt/apps/gesp-csp-quiz/.env` 读取生产 secret，模板为 `docker/.env.production.example`。
- 树莓派 compose 模板为 `docker/docker-compose.yml`，默认镜像是 ACR `latest`。

## 差异点

- 数据库分支不同：树莓派只能连接 Neon `production` branch，Fly 和本地只能连接 Neon `test` branch。
- 镜像 registry 不同：树莓派拉阿里云 ACR，Fly 由 Fly 自己构建和发布。
- 日志路径不同：树莓派 compose 默认把 `/usr/log/xzs/` 映射到宿主机 `./log`；Fly 日志主要看 `fly logs`。
- 密钥来源不同：树莓派 `.env` 在生产主机维护；Fly secret 由本机 `.env.neon-test` 导入。

## 验证入口

部署后统一验证：

```powershell
.\scripts\test-remote-deployment.ps1 -BaseUrl "<base-url>"
```

树莓派本机也可以直接检查：

```sh
curl -fsS http://127.0.0.1:8000/api/health
curl -I http://127.0.0.1:8000/student/index.html
curl -I http://127.0.0.1:8000/admin/index.html
```
