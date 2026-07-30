# 容器镜像部署公共说明

本文统一说明树莓派生产环境和 Fly 测试环境共用的容器镜像、运行参数和部署边界。

## 环境边界

| 环境 | 编排方式 | 镜像来源 | 数据库 |
| --- | --- | --- | --- |
| 树莓派生产 | `docker compose` | 阿里云 ACR `randolph87/gesp-csp-quiz` | Compose 内 PostgreSQL 18，数据位于 USB SSD |
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

2026-07-27 正式树莓派切换固定使用 ARM64 tag `986c8aa4`。生产切换入口拒绝
`latest`，后续切换和回滚也应使用明确 tag 或不可变 digest。由同一
`Dockerfile` 构建的 Fly release v15 已在 Neon `test` 环境通过测试。

Fly 测试环境也使用同一个 `Dockerfile`，但由 `flyctl deploy` 构建并推送到 Fly 自己的 registry：

```powershell
.\scripts\deploy-fly-neon-test.ps1
```

## 公共运行参数

以下变量在 Fly 和树莓派都使用相同语义：

- `SPRING_PROFILES_ACTIVE=prod`：运行打包后的生产形态配置。
- `SERVER_PORT=8000`：容器内部监听端口。
- `SPRING_DATASOURCE_URL`：数据库连接地址。树莓派 Compose 固定为内部
  `jdbc:postgresql://postgres:5432/<database>`；Fly 和本地仍使用 Neon test 原始 URL。
- `SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE`：连接池最大连接数。
- `SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE`：连接池最小空闲连接数。
- `XZS_AI_CONFIG_SECRET`：AI 配置 API Key 加密密钥，必须长期稳定。
- `XZS_LOG_PATH`：容器内日志目录。

不要在可提交文件中写入真实 `SPRING_DATASOURCE_URL`、数据库密码或 `XZS_AI_CONFIG_SECRET`。

## 模板入口

- Fly 测试环境从 `.env.neon-test` 读取测试 secret，部署入口为 `scripts/deploy-fly-neon-test.ps1`。
- 树莓派生产环境从 `/opt/apps/gesp-csp-quiz/.env` 读取本地数据库、USB SSD
  数据目录、备份目录和生产 secret，模板为 `docker/.env.production.example`。
- 树莓派 compose 模板为 `docker/docker-compose.yml`，默认镜像是 ACR `latest`。
- 树莓派影子验收使用同一 Compose 和 `docker/.env.shadow.example`，固定以
  `xzs-shadow` 独立 project 运行，只绑定 `127.0.0.1:18000`，不修改生产 project。

## 差异点

- 数据库链路不同：树莓派应用只连接 Compose 内部 PostgreSQL；Fly 和本地只连接
  Neon `test`。树莓派 `.env` 中的 `NEON_DR_DIRECT_URL` 仅供独立灾备刷新任务使用，
  不传给应用容器。
- 镜像 registry 不同：树莓派拉阿里云 ACR，Fly 由 Fly 自己构建和发布。
- 日志路径不同：树莓派 compose 默认把 `/usr/log/xzs/` 映射到宿主机 `./log`；Fly 日志主要看 `fly logs`。
- 密钥来源不同：树莓派 `.env` 在生产主机维护；Fly secret 由本机 `.env.neon-test` 导入。

根 `Dockerfile`、`fly.toml` 和 `scripts/deploy-fly-neon-test.ps1` 没有接入树莓派
`docker-compose.yml`，因此树莓派新增 PostgreSQL 服务不会让 Fly 启动本地数据库。

影子环境也只存在于树莓派 Compose 路线：独立 project、容器、网络、日志和 PostgreSQL
数据目录均与生产隔离。`deploy/raspberry-pi/docker/prepare-shadow-environment.sh`
只接受通过 archive、SHA-256 和 manifest 校验的 dump，并在恢复后启动当前应用镜像，
用于验证 PostgreSQL 18、JDBC 和 Flyway；清理入口默认保留影子数据。

Neon dump 可能包含本地 PostgreSQL 不提供的 `pg_session_jwt`。恢复辅助逻辑只允许
过滤该扩展自身的 `EXTENSION` 和 `COMMENT` 两类 TOC 项，并会拒绝不符合严格白名单的
组合；这不是通用的“忽略恢复错误”开关。

2026-07-27 已完成真实树莓派影子 PostgreSQL 18 恢复、影子功能及 5 轮 API、
真实 NAS 影子备份和隔离恢复。随后已通过
`deploy/raspberry-pi/docker/cutover-neon-to-local-postgres.sh` 正式切换生产到
Compose 内 PostgreSQL 18。首份小时备份 `xzs-20260727T090616Z.dump` 及隔离恢复报告
`restore-test-20260727T090623Z-26482.json` 均通过。小时备份和每周隔离恢复 timer
已启用，Neon DR timer 在 7 天观察期结束前未启用；旧 Neon 环境备份和独立停止态
回滚容器仍保留。

切换脚本必须传入固定镜像、USB SSD 数据根目录和
`--confirm CUTOVER_NEON_TO_LOCAL`；应先加 `--dry-run` 做只读预检。仅当根文件系统
已经确认位于 `/dev/sd*` 或 `/dev/nvme*` USB SSD 时才允许追加
`--allow-root-usb-ssd`。PostgreSQL bind 目录必须归容器用户 `999:999` 所有。脚本在
切换阶段失败时会恢复旧 Neon 环境并启动回滚容器。

最终公网生产 5 次测量已完成：`current` 中位数/P95 为 742.9/1968.0 ms，
较 Neon 基线快 2207.7 ms（74.8%）；`wrong` 为 1090.1/1860.4 ms，快
2796.7 ms（72.0%）；`workspace` 为 729.0/1642.4 ms，快 2105.7 ms
（74.3%）；`records` 为 748.7/1410.8 ms，快 2070.8 ms（73.4%）。

Playwright 首页、错题本翻页和考试记录只读流程通过，没有产生写入，控制台为
`0 errors`、`1` 条未分类 warning。最终 health 为 `UP`，应用和 PostgreSQL
restart count 均为 `0`；独立回滚容器已创建，两个本地 timer active，Neon DR
timer inactive；树莓派温度 39.9°C 且无降频。核心上线验收为 **PASS**，计划仍
保持 active 进行 7 天观察，并继续分类该 warning。

排查中暴露过的 Neon production 密码应在生产稳定后轮换，并只同步到未来 DR 专用
配置，任何文档和日志都不得写入真实凭据。

## 验证入口

统一验收入口会组合现有 HTTP 健康检查与 Playwright 公共页面冒烟检查。浏览器检查
只匿名打开学生端和管理端公共页面，验证主文档可加载、页面可见且没有 JavaScript
页面错误，并保存截图和 JSON 结果；默认不登录、不提交表单、不写业务数据。

按环境选择目标：

```powershell
.\scripts\test-deployment-acceptance.ps1 -Target Local
.\scripts\test-deployment-acceptance.ps1 -Target Fly
.\scripts\test-deployment-acceptance.ps1 -Target Raspi
```

也可以显式覆盖 URL；`-BaseUrl` 优先于所选目标的默认 URL：

```powershell
.\scripts\test-deployment-acceptance.ps1 `
  -BaseUrl "http://127.0.0.1:8000"
```

默认把 `http-check.txt`、公共页面截图、浏览器结果和总结果写入
`output/deployment-acceptance/<timestamp>-<target>/`。任一步失败都返回非零退出码，
并在错误信息中给出证据目录。只查看解析后的目标和检查步骤、不发网络请求时使用：

```powershell
.\scripts\test-deployment-acceptance.ps1 -Target Fly -Plan
```

原 `scripts/test-remote-deployment.ps1` 继续作为 HTTP 子检查入口保留，统一验收和
Fly 部署脚本会调用它。

## 本地到生产的晋级门

三个环境必须串行晋级，不能由一个脚本自动连续发布。树莓派生产发布始终需要单独、
明确的人工确认。

| 阶段 | 输入与动作 | 晋级条件 | 停止条件 | 回滚点 |
| --- | --- | --- | --- | --- |
| 本地开发 | 先通过既有构建与静态一致性命令，再使用 Neon `test` 启动当前候选版本并执行 `-Target Local` | 前置构建/静态一致性检查已单独通过，统一验收为 PASS，证据目录完整 | 任一前置检查失败，或统一验收的 HTTP、公共页面、页面错误检查失败 | 停止本地服务，修复代码或配置；不进入 Fly |
| Fly 测试 | 仅在本地通过后运行 `scripts/deploy-fly-neon-test.ps1`，仍连接 Neon `test` | Fly 部署完成，统一验收为 PASS，确认使用预期候选提交 | 部署失败、健康/页面失败、使用了错误数据库分支或证据不完整 | 回退 Fly 到上一个已通过的 release；不得申请树莓派发布 |
| 树莓派生产 | 仅在 Fly 通过后，固定不可变镜像 tag，人工确认后运行 `scripts/sync-raspi-production-env.ps1 -Restart -Verify` | 应用检查通过，且脚本证明 PostgreSQL 容器 ID 与重启计数前后完全一致；随后 `-Target Raspi` 统一验收为 PASS | PostgreSQL 容器缺失、被替换、重启计数变化，应用更新/健康/页面任一失败，或缺少明确生产确认 | 立即停止晋级；保留数据库不动，把 `XZS_IMAGE` 恢复为上一已知正常 tag，再通过同一 app-only 入口更新并复验 |

任一阶段失败后都只处理当前阶段，不继续下一环境。涉及数据库恢复、切换或灾备的
操作不属于日常应用发布，必须进入对应的独立高风险流程。
