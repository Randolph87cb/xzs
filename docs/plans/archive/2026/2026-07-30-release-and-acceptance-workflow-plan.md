# 发布与验收流程收敛计划

## 状态

- 当前状态：已完成
- 完成日期：2026-07-30
- 风险等级：L2（修改发布自动化与验收入口，但本轮不执行远端部署）
- 负责人：主线程负责编排、验收与 Git；实现 subagent 负责限定文件修改；独立验证 subagent 只读验收

## 背景

本周复盘发现 xzs 的发布与验收流程存在三类重复劳动和风险：

1. 树莓派日常更新入口在更新应用时会执行整个 Compose 的 `up -d`，边界大于实际需求，也缺少数据库容器未被重建或重启的硬性断言。
2. HTTP 健康检查已有脚本，Playwright 只读验收也做过多次，但没有一个可复用、可选择环境并统一保存证据的入口。
3. 本地、Fly 测试和树莓派生产之间缺少明确的阶段门、停止条件与回滚检查点，容易让一次任务边做边扩大范围。

## 目标

- 把树莓派普通应用发布收敛为只更新 `app` 服务，不重建、不重启 PostgreSQL。
- 在发布前后检查 PostgreSQL 容器身份和重启状态；异常时明确失败，不把部分成功描述成完成。
- 提供一个统一的部署验收入口，组合现有 HTTP 检查和只读 Playwright 浏览器冒烟检查，并把证据输出到明确目录。
- 文档化本地、Fly 测试、树莓派生产的晋级条件、停止条件和回滚点。

## 非目标与安全边界

- 本轮不执行 Fly 或树莓派部署。
- 本轮不连接、不修改任何生产数据库或 Neon 数据。
- 本轮不轮换或输出任何密码、连接串、API Key、SSH 凭据。
- 不把登录后会写数据的业务流程纳入默认浏览器验收。
- 不清理现有未跟踪的 `.playwright-cli/` 和 `output/`。
- 不修改教研中心项目。

## 实现范围

允许修改：

- `scripts/sync-raspi-production-env.ps1`
- `scripts/test-remote-deployment.ps1`
- `scripts/deploy-fly-neon-test.ps1`（仅在接入统一验收入口确有必要时）
- `scripts/` 下为统一验收新增的最少文件
- `docs/container-image-deployment.md`
- `docker/README.md`
- `frontend/package.json` 与 `frontend/scripts/`（仅在复用已有 Playwright 依赖更简单且无新增依赖时）
- `.gitignore`（仅用于忽略统一验收生成的证据目录）

禁止修改：

- `.env*`、数据库文件、备份文件、生产主机与任何远端环境
- `.playwright-cli/`、`output/`
- 与发布验收无关的业务代码和旧计划
- Git 历史、分支和远端（统一由主线程处理）

## Harness

### 输入

- 当前树莓派同步/发布脚本与 Compose 文档
- 当前远端 HTTP 验证脚本
- 前端已锁定的 Playwright 依赖和现有截图验证脚本
- 当前环境边界：本地和 Fly 使用 Neon test，树莓派使用 Compose 内 PostgreSQL 18

### 流程

1. 主线程固定计划、范围、风险和验收标准。
2. 一个实现 subagent 在限定文件内完成最小改动并执行离线验证。
3. 主线程核对真实 diff、状态、边界与验证证据。
4. 一个独立验证 subagent 只读审查并复跑关键验证。
5. 如有明确缺陷，仅回派原实现 subagent 修复一次，再由主线程复验。
6. 主线程更新计划状态，串行执行 Git 提交与推送。

### 并发与重试

- 实现阶段并发数：1。
- 验证阶段并发数：1。
- subagent 阶段上限：实现、独立验证、必要时一次修复。
- 禁止为同一问题继续扩增 subagent；验证失败时优先缩小问题并回派原实现者。

## 验收标准

### 树莓派应用发布

- 拉取和更新命令只针对 `app` 服务，启动命令使用不联动依赖服务的语义。
- 更新前后记录 PostgreSQL 容器 ID 与重启计数；容器被替换、消失或重启计数变化时发布失败。
- `-Restart`、`-SkipPull`、`-Verify` 和 `-ShadowAssetsOnly` 的既有边界保持清晰。
- 能在不连接树莓派、不读取真实 secret 的情况下验证生成的远端命令或关键行为。

### 统一验收

- 一个命令可选择本地、Fly 或树莓派目标，并能显式覆盖 `BaseUrl`。
- 默认执行现有 HTTP 健康检查和学生端、管理端公共页面浏览器只读冒烟检查。
- Playwright 检查至少验证页面可加载、无页面错误，并生成截图或等价可复核证据。
- 默认验收不登录、不写业务数据；需要登录的深度验收必须是显式可选项并有单独边界。
- 浏览器层必须在请求离开浏览器前阻止非 `GET`、`HEAD`、`OPTIONS` 方法，不能只在请求发出后记录并报错。
- 失败时返回非零退出码，证据路径和失败步骤清晰。
- 默认证据目录被 Git 忽略，不持续污染工作区。

### 阶段门

- 本地通过后才能进入 Fly；Fly 通过后才能申请树莓派生产发布。
- 树莓派生产发布始终需要单独明确确认，不能由本地或 Fly 脚本自动串联触发。
- 每一阶段明确输入、验证、停止条件和回滚点。

### 验证

- 所有修改过的 PowerShell 文件通过语法解析。
- Playwright 入口的帮助或离线参数校验可运行。
- 不执行真实 Fly/树莓派部署的情况下，能证明应用更新命令不会操作 PostgreSQL。
- 文档命令与脚本参数保持一致。
- `git diff --check` 通过。

## 完成记录

- 树莓派普通发布已收敛为 `pull app` 与 `up -d --no-deps app`，并在应用更新前后核对 PostgreSQL 容器 ID 和 `RestartCount`。新增 `-RenderRestartPlan` 后，可以在不读取 `.env`、不建立 SSH 连接的情况下验收真实命令块。
- 新增 `scripts/test-deployment-acceptance.ps1` 统一入口和匿名 Playwright 公共页面检查，可选择 Local、Fly、Raspi 或显式 URL，统一记录 HTTP、浏览器截图和 JSON 证据。
- 浏览器使用路由拦截，在非 `GET`、`HEAD`、`OPTIONS` 请求离开浏览器前终止请求；发现写请求时验收失败。
- Fly secret 导入、旧 secret 移除和部署命令均显式检查原生命令退出码，不再可能在部署失败后继续验收旧版本。
- 文档已补齐本地、Fly、树莓派的串行晋级门、停止条件和回滚点；生产发布仍需单独明确确认。
- `.gitignore` 只忽略统一验收生成的 `/output/deployment-acceptance/`，未处理既有 `output/` 内容或 `.playwright-cli/`。

验证结果：

- 相关 PowerShell 文件在 PowerShell 7 通过语法解析；统一入口与树莓派离线计划在 Windows PowerShell 5.1 可执行。
- `-RenderRestartPlan` 的默认、`-SkipPull`、`-Verify` 组合均通过离线断言：只更新 app，包含 PostgreSQL 前后保护，不含全栈 `up`。
- 统一入口的 Local、Fly、Raspi、Custom 计划解析及非法 URL、含凭据 URL、矛盾跳过参数的负向检查通过。
- 本地临时 HTTP 服务上的 HTTP + Playwright 双页面验收通过，共验证两个公共页面。
- 本地页面主动发起 POST 的负向用例按预期失败，浏览器记录 1 个被阻断请求，服务端实际收到的写请求数为 0。
- `git diff --check` 通过。
- 全程未部署 Fly 或树莓派，未访问 Neon，未读取或输出任何真实 secret。

Harness 复盘：

- 本轮严格保持单实现者、单验证者，避免了并发写冲突。
- 两个 subagent 都在环境验证阶段超过等待窗口；主线程没有继续扩增 agent，而是中止长等待、复用原实现者做一次定点返修，并接管最终浏览器实跑。
- 后续同类任务应把“每条环境命令最长 45 秒，超时立即返回已有证据”写进启动提示，并要求 agent 在主体修改完成后先发阶段状态，避免验证命令吞掉整个回报窗口。
