# 树莓派生产数据每日刷新到 Neon 方案

状态：active
创建日期：2026-08-04
完成日期：
验证摘要：仓库实现与本地离线验收已 GO：生产刷新失败门 18/18、`test` reset 状态机 19/19、PowerShell 部署失败门和 timer 回滚验证通过。用户已确认每日刷新 Neon `production`，成功后 reset `test`，并接受 `test` 临时写入被覆盖。尚未安装远端 unit、执行首次真实刷新或启用 timer。

## 背景与现状

- 树莓派生产应用使用 Docker Compose 内的 PostgreSQL 18，是唯一生产主写入库。
- 生产库每小时备份到极空间；远端检查确认本地备份 timer 已启用。
- 树莓派 `.env` 已存在 `NEON_DR_DIRECT_URL`，但对应目标与 Fly、本地开发使用的 Neon `test` 分支不同。
- `xzs-neon-dr-refresh.timer` 当前未安装、未启用、未运行。
- 仓库已有“最新 dump 恢复到 Neon DR”的脚本和每日 timer 模板，但现有脚本仅检查 URL 格式和非 pooled 地址，不能证明目标就是预期 DR，且没有完整消费 `latest.json`、manifest、备份年龄和目标行数对账。
- Fly 与本地开发固定连接 Neon `test`；即使每日刷新 Neon DR，Fly 测试数据也不会自动变化。

## 结论

采用两级刷新：先把最新验证备份安全、每日恢复到隔离的 Neon DR/父分支；若用户明确接受每天丢弃 Neon `test` 写入和短暂测试中断，再把 `test` 子分支从父分支 reset。不得让 Fly 直接连接 DR，也不得未经确认直接对 `test` 执行 `pg_restore --clean`。

## Harness 定界

- 风险等级：L3，涉及生产数据副本、远端数据库覆盖、systemd 定时任务和外部服务。
- 任务形态：复杂分阶段。
- 主线程：定界、方案、阶段验收、Git、外部写操作授权、部署和上线后观察。
- 实现 subagent：只修改仓库内刷新脚本、unit、模板和测试，不执行 Git、树莓派或 Neon 写操作。
- 部署集成 subagent：提供独立 secret 模板和可重复部署入口；默认仅安装、离线预检并
  保持 timer 禁用，首次人工周期和 timer 启用分别要求显式确认参数。
- 独立验证 subagent：验证失败门、目标隔离、备份族校验、日志脱敏、定时行为和部署后状态。
- 外部写操作：首次 DR 恢复、`test` reset、timer 安装/启用必须串行，并在各自检查点通过后由主线程执行。
- Git 策略：实现和独立验证通过后由主线程提交并 push；不得提交任何 secret 或测试输出。

## 需求拆解

### 1. 加固每日 Neon DR 刷新

- 当前现状：已有 destructive confirm、非 pooled URL 检查、archive 与 SHA-256 检查，但目标隔离、manifest、备份年龄、NAS 挂载实证、跨任务互斥和恢复原子性不足。
- 判断：现状为 NO-GO，不能直接安装并启用 timer。
- 修改方案：
  - 使用独立 root `0600` 环境文件加载 DR URL，不让刷新 service 继承完整生产 `.env`。
  - 配置预期 Neon project/branch/endpoint 的非敏感指纹；刷新前计算实际目标指纹并严格比较，同时拒绝已知 `test` 目标。
  - 从原子发布的 `latest.json` 选择小时备份，限定路径必须位于 `hourly`，备份年龄不超过 3 小时。
  - 验证 dump、SHA-256、manifest、Flyway 版本和关键表行数；NAS 路径必须由 `findmnt`/`mountpoint` 证明是预期挂载。
  - 为备份、隔离恢复和 DR 刷新使用共享运维锁；人工与 timer 调用也不能并发。
  - 恢复使用单事务模式；失败时保留上一份可用 Neon 恢复点，不把半恢复目标标为成功。
  - 成功后原子写入不含凭据的 `last-success.json`，记录源备份时间、摘要、目标指纹、行数和完成时间。
  - timer 每日执行一次，默认 04:45 并带随机延迟；共享锁负责避开小时备份和每周隔离恢复。
- 影响范围：`deploy/raspberry-pi/docker` 下公共脚本、刷新脚本和 systemd unit；Docker 环境模板与部署文档。
- 验证方案：
  - Bash 语法和 ShellCheck；脚本夹具覆盖陈旧备份、缺失 sidecar/manifest、错误 checksum、路径越界、NAS 未挂载、错误目标和并发锁。
  - 只读 preflight 必须在零数据库写入下通过；对已知 `test` 指纹必须失败。
  - 首次人工刷新后对账 Flyway、关键表行数和孤立记录，并确认 journal/状态文件不含 URL、密码、Token 或业务数据。

### 2. 每日更新 Fly 使用的 Neon `test`

- 当前现状：DR 与 `test` 是不同目标；项目没有 Neon API key、project/branch ID 或自动 reset 脚本。
- 判断：这是独立的破坏性流程。Neon 官方 branch reset 会完整覆盖子分支，丢弃其现有测试写入，并在 reset 期间短暂中断连接；匹配角色在子分支中的密码可以保留。
- 修改方案：
  - 仅在确认 `test` 是预期父分支的子分支后使用 Neon CLI/API reset，不向在线 `test` 直接运行 `pg_restore --clean`。
  - API token、project ID、父/子 branch ID 放入独立 root `0600` 环境文件；脚本严格核验分支父子关系和保护状态。
  - reset 前保留可回滚分支或快照；reset 后等待 endpoint 恢复并执行 Fly 健康、登录页、Flyway 和关键表只读校验。
  - 每日 reset 必须在 DR 刷新成功且源备份未过期后触发；DR 失败时不得继续更新 `test`。
  - 默认不做数据脱敏；若测试环境不能承载生产学生数据，则改为单独的脱敏导入流程，不执行完整 branch reset。
- 影响范围：新增 test branch reset 脚本和 unit、独立 Neon API 配置、Fly 部署验收脚本与文档。
- 验证方案：
  - 在临时子分支演练 reset、回滚、密码保持和短暂断连恢复。
  - 确认 reset 前测试写入会被删除，并由用户接受该行为。
  - Fly 上执行健康检查、公共页面、启动日志和只读数据新鲜度检查。

## 执行顺序

1. 用户确认每日刷新目标及 `test` 数据覆盖政策。
2. 实现 subagent 加固 DR 刷新脚本、unit、模板和测试。
3. 主线程验收实现范围和本地失败门。
4. 独立验证 subagent 统一验证仓库产物，失败项集中返修一次。
5. 主线程提交并 push。
6. 从 `docker/.env.neon-production-refresh.example` 建立被忽略的本地专用 secret，
   通过 `scripts/deploy-raspi-neon-refresh.ps1` 安装 ops、unit 和远端 root `0600`
   环境文件；默认只做离线 preflight，并保持 timer 禁用。
7. 建立 Neon 侧回滚点，再显式传 `-RunOnce` 和确认词执行首次人工周期。人工 unit
   严格先刷新 production，成功后才以 `--preserve-current` reset test，并完成数据
   对账和日志脱敏检查。
8. 至少 7 天稳定观察完成后，单独显式传 `-EnableTimer`、启用确认词和观察期确认开关；
   日常 unit 不保留旧 test 分支。验证下次触发计划后观察首次自动运行。
9. 连续观察至少两次自动周期，确认 DR/test 新鲜度、Fly 可用性和失败告警。

## 检查点与停止条件

- DR 目标与 `test` 或历史回滚目标无法证明隔离：停止。
- 最新备份超过 3 小时、NAS 非预期挂载或备份族不完整：停止，不刷新旧数据。
- 没有 Neon 侧回滚点、首次人工刷新未对账或日志泄露凭据：停止，不启用 timer。
- 未明确接受 `test` 写入每日丢失：只完成 DR 定时刷新，不实施 `test` reset。
- 任一自动周期失败：保留上一可用目标，禁止级联刷新 `test`，记录失败并等待处理。

## 风险与待确认

- 已确认：每天自动覆盖 Fly 使用的 Neon `test` 分支，接受所有测试写入在下一次 reset 时丢失和连接短暂中断。
- 需要确认 Neon `test` 与准备每日刷新的父分支存在可 reset 的父子关系；否则需先调整 Neon 分支结构。
- 需要确认生产学生数据是否允许完整进入公开测试环境；若不允许，必须先定义账号、姓名、联系方式和答题记录的脱敏规则。
- Neon API key、branch ID 和 direct URL 只能写入被忽略的本地/远端 secret 文件，不能进入 Git、日志或聊天。

## 收尾记录

- 完成状态：执行中；仓库实现和离线验收已 GO，等待专用 Neon secret 配置后进入远端安装、只读 preflight 和首次人工周期。
- 归档日期：
- 归档原因：
