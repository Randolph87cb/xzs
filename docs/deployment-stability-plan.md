# 部署稳定性改进方案

## 背景与现状

- 当前环境边界已确定：树莓派是生产环境，连接 Neon `production` branch；Fly.io 是测试环境，连接 Neon `test` branch；本地是开发环境，连接 Neon `test` branch。
- 当前生产运行目录为 `/opt/apps/gesp-csp-quiz`，通过 `docker compose` 运行 `xzs-app`，镜像来自阿里云 ACR `randolph87/gesp-csp-quiz`。
- Fly 测试环境通过 `scripts/deploy-fly-neon-test.ps1` 从 `.env.neon-test` 导入测试 secrets 并部署。
- 树莓派生产环境通过 `scripts/sync-raspi-production-env.ps1` 同步 `docker/.env.production` 和 `docker/docker-compose.yml`，再远程执行 compose 校验、重启和健康检查。
- 最近一次生产部署暴露的问题包括：远端 compose 没有随本地模板同步、`.env` 中 `$` 被 compose 变量插值、ACR 域名在树莓派上偶发 DNS 解析失败、新版本启动失败时需要人工回滚判断。

## 结论

推荐把部署收敛成三个固定入口：本地开发只用 `start-local-neon`，Fly 测试只用 `deploy-fly-neon-test`，树莓派生产只用一个新的生产发布脚本。生产发布脚本应完成“构建镜像、推送、同步 compose/env、预拉镜像、切换固定 tag、健康检查、失败自动回滚、记录发布信息”完整闭环。

## 需求拆解

### 1. 固定三环境边界

- 当前现状：`docs/container-image-deployment.md` 和 `docker/README.md` 已写明环境边界，但还缺少一个执行层面的总入口说明。
- 判断：环境隔离原则已经清楚，风险在于实际操作时绕过固定脚本，导致生产误连测试库、Fly 误连生产库，或远端 compose 与仓库不同步。
- 修改方案：
  - 新增或更新 `docs/deployment-runbook.md`，明确三条唯一推荐路径。
  - 本地开发：`scripts/start-local-neon.ps1`，只读取 `.env.neon-test`。
  - Fly 测试：`scripts/deploy-fly-neon-test.ps1`，只读取 `.env.neon-test`。
  - 树莓派生产：新增 `scripts/deploy-raspi-production.ps1`，只读取 `docker/.env.production`。
  - 在脚本中增加环境防呆：测试脚本拒绝疑似 production Neon host，生产脚本拒绝疑似 test Neon host。
- 影响范围：部署文档、PowerShell 脚本、CI/手工发布流程。
- 验证方案：分别用 dry-run 或配置校验模式确认三个入口只读取对应 env 文件，并在错误 branch host 时失败。

### 2. 生产发布脚本闭环

- 当前现状：生产发布需要先构建推送镜像，再同步树莓派 env/compose，再重启验证；步骤分散，失败后依赖人工继续。
- 判断：生产发布应有一个主入口，避免遗漏 compose 同步、健康检查或回滚。
- 修改方案：
  - 新增 `scripts/deploy-raspi-production.ps1`，内部调用或复用 `sync-raspi-production-env.ps1`。
  - 默认 tag 使用当前 Git 短提交号，不直接把生产固定在不可追踪的 `latest`。
  - 构建时同时推送 `<git-sha>` 和 `latest`，但远端 `.env` 中 `XZS_IMAGE` 写入 `<git-sha>`。
  - 部署步骤固定为：
    1. 检查工作区状态，默认要求干净。
    2. 执行后端和前端构建校验。
    3. 构建并推送 `linux/arm64` 镜像。
    4. 同步 `docker-compose.yml` 和 compose-safe `.env`。
    5. 远端 `docker compose config`。
    6. 远端 `docker compose pull app`。
    7. 远端切换到新 tag 并启动。
    8. 轮询 `/api/health`、学生端和管理端入口。
    9. 失败时恢复上一个 `.env` 和 `docker-compose.yml`，执行 `docker compose up -d`，再验证旧版本。
  - 脚本输出发布摘要：tag、镜像 digest、远端备份目录、健康检查结果、是否发生回滚。
- 影响范围：新增发布脚本，扩展现有同步脚本参数和输出格式。
- 验证方案：在树莓派上用当前版本执行一次无业务变更发布；人为传入不存在的 tag 验证自动回滚；验证公网 `scripts/test-remote-deployment.ps1` 通过。

### 3. 镜像和回滚策略

- 当前现状：文档建议同时推送 `latest` 和 Git 短提交 tag，但生产实际容易使用 `latest`。
- 判断：生产用 `latest` 不利于定位和回滚，尤其在 ACR 或本地缓存异常时不清楚运行的是哪个版本。
- 修改方案：
  - 生产 `.env` 固定写 `XZS_IMAGE=<registry>/<repo>:<git-sha>`。
  - `latest` 只作为人工快速测试或首次拉取便利 tag，不作为生产锁定版本。
  - 远端每次发布自动保存 `releases/<timestamp>.json`，记录 tag、镜像名、Git commit、部署结果和备份目录。
  - 提供 `scripts/rollback-raspi-production.ps1 -Tag <git-sha>`，支持回滚到指定 tag 或最近一次成功发布。
- 影响范围：生产 env 生成逻辑、部署文档、回滚脚本。
- 验证方案：部署一个指定 tag 后检查 `docker compose ps` 中镜像 tag；回滚到上一 tag 后确认健康检查通过。

### 4. 配置与密钥管理

- 当前现状：真实生产配置由 `docker/.env.production` 本地维护并复制到树莓派；`.env` 中特殊字符已经需要 compose-safe 转换。
- 判断：可以继续保留本地填写、脚本复制的流程，但脚本必须承担转义、校验和脱敏输出。
- 修改方案：
  - `docker/.env.production` 继续 Git 忽略，只保留 `docker/.env.production.example`。
  - 生产脚本读取真实 env 后生成临时 compose-safe 文件，不改写本地真实文件。
  - 所有脚本输出只打印变量名、缺失项、校验结果，不打印完整连接串或 secret。
  - 对 `XZS_AI_CONFIG_SECRET` 增加长度校验；对 `SPRING_DATASOURCE_URL` 增加 `sslmode=require`、Neon branch host 规则校验。
- 影响范围：生产部署脚本、env 模板、文档。
- 验证方案：构造含 `$` 的本地 env，确认远端 `docker compose config` 不再出现变量插值警告；构造缺失 secret 或错误 branch host，确认脚本提前失败且不输出 secret。

### 5. ACR 和树莓派网络稳定性

- 当前现状：树莓派曾出现 ACR 域名 DNS 解析失败，但本地已有镜像时可用 `-SkipPull` 完成重启。
- 判断：`-SkipPull` 只能作为应急方案，正式发布仍应先确保远端可拉到指定 tag。
- 修改方案：
  - 生产脚本在远端 pull 前先做 DNS 和 registry 连通性检查。
  - 失败时直接停止发布，不切换容器；如果本地已有同 tag 镜像，可要求显式 `-UseCachedImage` 才允许继续。
  - 文档中记录树莓派 DNS 修复入口，例如检查 `/etc/resolv.conf`、路由器 DNS、Docker daemon DNS。
- 影响范围：生产部署脚本、故障排查文档。
- 验证方案：断开或模拟 registry 失败时，脚本应在启动前失败，并保持当前生产容器不变。

### 6. 发布前后验证

- 当前现状：已有 `scripts/test-remote-deployment.ps1` 能验证公网 health、学生端、管理端。
- 判断：还需要把验证嵌入发布脚本，并补充远端容器状态和日志检查。
- 修改方案：
  - 发布前：本地 `mvn package` 或统一 build 脚本、前端静态资源一致性校验、Docker build 成功。
  - 发布中：远端 `docker compose config`、`docker compose ps`、健康检查轮询。
  - 发布后：公网 `scripts/test-remote-deployment.ps1`，远端 `docker logs --tail=120 xzs-app` 只在失败时输出并脱敏。
  - 可选增加一个只读 smoke API，检查数据库、登录页静态资源、关键后端版本信息。
- 影响范围：发布脚本、健康检查接口或版本信息输出。
- 验证方案：正常发布应一次通过；应用启动失败时脚本应输出失败阶段、日志摘要并完成回滚。

### 7. 文档与操作习惯固化

- 当前现状：`docs/container-image-deployment.md`、`docker/README.md`、`docs/raspberry-pi-deployment.md` 有部分重叠，且 `raspberry-pi-deployment.md` 仍偏 systemd/Jar 历史路线。
- 判断：需要把“当前事实来源”和“历史路线”区分得更明确。
- 修改方案：
  - 新增 `docs/deployment-runbook.md` 作为当前日常部署唯一入口。
  - 更新 `docs/container-image-deployment.md`，补充生产固定 tag、自动回滚、远端 compose 同步要求。
  - 在 `docs/raspberry-pi-deployment.md` 顶部加醒目说明：当前默认生产是 Docker Compose，systemd/Jar 仅历史参考。
  - 更新 `AGENTS.md` 中部署入口说明，要求以后生产部署先走 `deploy-raspi-production.ps1`。
- 影响范围：部署文档、项目协作规则。
- 验证方案：按 runbook 从零执行一次测试发布和一次生产发布；确认不需要翻聊天记录。

## 推荐执行顺序

1. 文档收敛：新增 `docs/deployment-runbook.md`，更新现有部署文档的入口关系。
2. 脚本收敛：新增 `scripts/deploy-raspi-production.ps1`，把构建、推送、同步、验证、回滚串起来。
3. 环境防呆：给本地、Fly、生产脚本增加 Neon branch host 校验和 secret 校验。
4. 固定 tag：生产发布不再默认运行 `latest`，改为运行 Git 短提交 tag。
5. 自动回滚：部署失败自动恢复上一个备份目录，并重新验证旧版本。
6. 连通性检查：补齐 ACR DNS/registry 检查和 `-UseCachedImage` 应急开关。
7. 演练：执行一次正常发布、一次失败回滚演练、一次公网 smoke test。

## 风险与待确认

- 生产脚本是否允许在 Git 工作区有未提交改动时发布：推荐默认拒绝，必要时显式 `-AllowDirty`。
- 是否需要把生产发布从本机脚本迁移到 GitHub Actions：短期不建议，因为目前依赖本机 `docker/.env.production` 和 Cloudflare SSH；等手工脚本稳定后再迁移 CI。
- 树莓派 ACR DNS 偶发失败是否需要主机级修复：建议先在脚本里做发布前检查；如果再次出现，再固定 Docker daemon DNS 或路由器 DNS。
- Neon production 的备份策略不在本方案内，需要单独补充数据库备份和恢复演练方案。
