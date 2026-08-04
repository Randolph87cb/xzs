# 树莓派本地 PostgreSQL、极空间 NAS 备份与 Neon 灾备方案

状态：active
创建日期：2026-07-26
完成日期：
验证摘要：2026-07-27 已完成影子恢复、真实 NAS 备份/隔离恢复、生产切换、最终
公网生产 5 轮 API 和真实浏览器只读验收，核心上线结论为 PASS。计划保持 active，
继续 7 天稳定观察并分类 1 条未分类 warning。

## 背景与现状

- 当前生产应用部署在树莓派，使用 Docker Compose 运行 `xzs-app`，生产目录是 `/opt/apps/gesp-csp-quiz`。
- 2026-07-27 已把生产应用从 Neon `production` branch 正式切换到同一 Compose
  项目中的本地 PostgreSQL 18；Fly.io 和本地开发仍连接 Neon `test` branch。
- 已确认树莓派是 `aarch64`，有约 8 GB 内存，温度、负载和降频状态正常；
  PostgreSQL 数据目录使用 USB SSD 的显式 bind 路径，并由容器内 PostgreSQL 用户
  `999:999` 持有。
- 切换前测得树莓派访问 Neon 的简单数据库往返中位数约为 232 ms，而树莓派本机
  静态请求约为 6 ms。正式影子对比数据见“性能收益预期”。
- 本方案把 `/mnt/zspace-xzs-backup` 视为已经稳定挂载、容量充足且可由备份服务写入的外部存储；NAS 协议、挂载、权限、容量、快照和设备运维不纳入本文范围。
- 项目内已有旧的本机 PostgreSQL `pg_dump`/`pg_restore` 脚本，但它们对应历史 systemd/Jar 路线，不能直接套用到当前 Docker Compose 生产部署。
- 当前 `docker/docker-compose.yml` 已包含应用和本地 PostgreSQL 18，数据库不映射
  宿主机 `5432`；备份、恢复演练和正式切换由 Docker 路线运维脚本负责。
- Neon production 在迁移时使用 PostgreSQL 18.4，本地保持 PostgreSQL 18。
  正式切换固定使用 ARM64 应用镜像 tag `986c8aa4`；同一 `Dockerfile` 构建的 Fly
  release v15 已在 Neon `test` 环境通过测试。

## 结论

树莓派 USB SSD 上的 PostgreSQL 已作为唯一生产主库，极空间作为本地异机备份文件库；
Neon 旧生产环境暂保留为切换观察期回滚来源，未来使用独立配置作为异地冷灾备。
当前已确认可以接受不超过 1 小时的数据损失窗口，因此采用“每小时逻辑备份到极空间 +
稳定后每日刷新 Neon”的路线，不把连续 WAL/PITR 纳入本轮实施。

不建议：

- 不把 PostgreSQL 实时数据目录放在外部备份目录。
- 不让应用同时写树莓派和 Neon。
- 不直接把未验证的 dump 覆盖到 Neon。
- 不把单一备份副本或 Neon 当前数据副本当成完整备份。
- 不在公网开放树莓派 PostgreSQL 的 `5432` 端口。

## 目标架构

```text
公网用户
   |
Cloudflare / 当前公网入口
   |
树莓派 xzs-app
   |
Docker 内部网络（不开放 5432）
   |
树莓派 PostgreSQL 18（USB SSD，本地唯一主写入库）
   |
   +-- 每小时 pg_dump 自定义格式 --> 树莓派本地暂存
   |                                  |
   |                                  +-- 校验后原子复制 --> 极空间 NAS
   |
   +-- 每日已验证 dump -------------> Neon production 灾备库
   |
   +-- 重要变更前后手动备份 --------> 极空间 + Neon

Fly.io 应用 + Neon test
   |
仅作为测试环境，不接入生产写入链路
```

## 恢复目标

第一阶段建议接受以下目标：

| 故障场景 | 恢复来源 | 目标 RPO | 预估 RTO | 说明 |
| --- | --- | ---: | ---: | --- |
| 应用容器故障 | 本地 PostgreSQL | 0 | 5–15 分钟 | 只恢复或回滚应用镜像 |
| PostgreSQL 容器故障、数据目录正常 | 本地数据目录 | 0 | 10–30 分钟 | 重建容器并挂回数据目录 |
| 树莓派数据库数据损坏 | 极空间最新小时备份 | 不超过 1 小时 | 30–90 分钟 | 在新库恢复并验证后切换 |
| 树莓派整机或 USB SSD 损坏 | 极空间备份 | 不超过 1 小时 | 1–4 小时 | 取决于替代主机准备时间 |
| 树莓派与极空间同时不可用 | Neon 灾备 | 不超过 24 小时 | 15–60 分钟 | 切换连接配置并启动应用 |
| 误删或错误批量修改 | 极空间历史备份 | 1 小时到指定历史版本 | 30–90 分钟 | 不使用最新副本覆盖历史 |

以上时间是当前数据规模下的方案目标，不是实施前保证值。影子恢复和故障演练完成后，应把实测值回填到本文档。

当前目标是小时级恢复点，暂不实施连续 WAL/PITR。只有未来业务明确要求最多只丢 5–10 分钟数据时，才重新评估 pgBackRest 或等价成熟工具。PostgreSQL 官方将 SQL dump、文件系统备份和连续归档列为三类不同的备份方式：

- <https://www.postgresql.org/docs/18/backup.html>

## 性能收益预期

本方案的 NAS 和 Neon 备份任务不进入用户请求链路。数据库读取和写入全部走树莓派 Docker 内部网络。

| 被优化位置 | 当前观测 | 本地数据库目标 | 预期变化 |
| --- | ---: | ---: | ---: |
| 单次简单数据库往返 | 约 232 ms | 1–10 ms | 减少约 220 ms，约 95% |
| 包含两次鉴权 SQL 的受保护接口 | 仅鉴权约叠加 400–500 ms | 约 2–20 ms | 接口基础等待减少约 400 ms |
| 错题本后端查询链路 | 约 5 次 SQL 往返 | 本地 SQL | 预计减少约 1–2 秒 |
| 错题本从进入到可操作 | 树莓派公网实测约 8 秒 | 目标 3–5 秒 | 预计改善约 35%–60% |
| 考试记录、答卷列表 | 多次远程 SQL | 本地 SQL | 预计减少数百毫秒到 1 秒以上 |

公网 Cloudflare 入口、前端渲染和仍存在的串行接口不会被本地数据库自动消除，因此迁移后必须按相同账号、相同页面和相同数据重新测量，不能把全部 8 秒都算作数据库收益。

2026-07-27 影子环境已完成相同数据下的功能检查和每项 5 轮 API 对比，记录值如下，
单位为毫秒：

| 场景 | 树莓派 + Neon 基线 | 影子本地 PostgreSQL |
| --- | ---: | ---: |
| `current` | 2950.6 | 1595.6 |
| `wrong` | 3886.8 | 2337.8 |
| `workspace` | 2834.7 | 1651.6 |
| `records` | 2819.5 | 2105.8 |

该结果证明本地数据库方向有效。正式切换后又完成公网生产每项 5 次测量：

| 场景 | 生产中位数（ms） | 生产 P95（ms） | 相对树莓派 + Neon 基线 |
| --- | ---: | ---: | ---: |
| `current` | 742.9 | 1968.0 | 快 2207.7 ms / 74.8% |
| `wrong` | 1090.1 | 1860.4 | 快 2796.7 ms / 72.0% |
| `workspace` | 729.0 | 1642.4 | 快 2105.7 ms / 74.3% |
| `records` | 748.7 | 1410.8 | 快 2070.8 ms / 73.4% |

Playwright 首页、错题本翻页和考试记录只读流程通过，未产生写入；控制台记录
`0 errors`、`1` 条未分类 warning。该 warning 不阻塞核心上线 PASS，但需在观察期
内分类。

## 需求拆解

### 1. 树莓派本地 PostgreSQL Docker 服务

- 当前现状：
  - 已完成：Compose 包含 `xzs-app` 与 PostgreSQL 18，应用通过内部
    `postgres:5432` 访问本地主库。
  - 已完成：实时数据位于 USB SSD 显式 bind 目录，不在 SD 卡或 NAS；目录属主是
    容器内 PostgreSQL 用户 `999:999`。
- 判断：
  - 应在同一个 compose 项目中新增 PostgreSQL 服务，通过 Docker 内部网络连接。
  - 数据目录必须明确绑定到 USB SSD 的实际挂载路径，不能使用无法确认物理位置的匿名卷，也不能落到 SD 卡。
- 修改方案：
  - 修改 `docker/docker-compose.yml`：
    - 新增 `postgres` 服务。
    - 使用与 Neon production 相同主版本的官方 ARM64 PostgreSQL 镜像，并固定小版本或 digest。
    - `PGDATA` 绑定到 USB SSD，例如 `${XZS_POSTGRES_DATA_DIR}/data`；真实路径在实施前根据 `/dev/sda2` 挂载点确定。
    - 不配置宿主机 `5432:5432` 端口映射。
    - 增加 `pg_isready` 健康检查。
    - 应用服务等待数据库健康后启动。
    - 应用改用 `jdbc:postgresql://postgres:5432/xzs`，用户名和密码分开配置。
  - 修改 `docker/.env.production.example`：
    - 删除“生产必须连接 Neon”的旧默认说明。
    - 增加本地数据库名、用户、密码、数据目录变量。
    - Neon 灾备连接串使用独立变量，且只供备份恢复任务使用。
  - 数据库初始资源限制采取保守值，先运行再测：
    - PostgreSQL 最大连接数控制在 30 左右。
    - 应用 Hikari 最大连接池先保持 4。
    - 不在首轮盲目增大 `shared_buffers`、`work_mem` 和 JVM 堆。
  - PostgreSQL 数据目录和本地备份暂存目录分开：

    ```text
    <USB-SSD>/xzs/postgres/data
    <USB-SSD>/xzs/backup-staging
    ```

- 影响范围：
  - `docker/docker-compose.yml`
  - `docker/.env.production.example`
  - 树莓派 `/opt/apps/gesp-csp-quiz/.env`
  - USB SSD 挂载和目录权限
  - `docs/container-image-deployment.md`
  - `docker/README.md`
  - `docs/project-structure/database-deploy.md`
- 验证方案：
  - `docker compose config` 通过且不打印真实密码。
  - PostgreSQL 和应用容器均为 healthy。
  - 宿主机和公网不能直接连接 `5432`。
  - 重启容器和树莓派后数据仍存在。
  - 确认 PostgreSQL 数据目录实际位于 USB SSD，而不是 SD 卡或 NAS。
  - 记录本地 `select 1`、登录、错题本、考试记录和答题提交耗时。

### 2. 每小时备份到极空间

- 当前现状：
  - 旧 `deploy/raspberry-pi/backup-db.sh` 面向 systemd/Jar 部署，并假设宿主机安装 PostgreSQL 客户端。
  - Docker Compose 路线的 custom dump、校验、manifest、NAS 原子发布和分层保留
    已实现并通过真实极空间验证。
  - 生产切换后的首份小时备份 `xzs-20260727T090616Z.dump` 已生成并通过校验；
    `xzs-postgres-backup.timer` 已启用。
- 判断：
  - 当前数据库规模较小，第一阶段每小时完整逻辑备份的复杂度最低，足以把主要 RPO 控制在 1 小时内。
  - 不能把 `pg_dump` 输出直接写到 NAS 最终文件；网络中断会留下看似存在但不完整的文件。
- 修改方案：
  - 新增 Docker 路线备份脚本，例如：
    - `deploy/raspberry-pi/docker/backup-postgres-to-zspace.sh`
    - `deploy/raspberry-pi/docker/verify-postgres-backup.sh`
    - `deploy/raspberry-pi/docker/restore-postgres-backup.sh`
  - 备份流程：
    1. 使用 `flock` 防止任务重叠。
    2. 在 USB SSD 暂存目录生成 `pg_dump --format=custom --no-owner --no-privileges`。
    3. 检查退出码、文件非空、`pg_restore --list` 可读取。
    4. 生成 SHA-256 校验值。
    5. 生成 manifest，至少包含备份时间、数据库版本、应用镜像 tag、Flyway schema 版本、文件大小、校验值和关键表行数。
    6. 先复制成 NAS `incoming/*.partial`。
    7. 校验 NAS 文件 SHA-256。
    8. 原子改名进入 `hourly/`。
    9. 只有成功后才更新 `latest.json` 和最后成功时间。
  - 使用 systemd timer，而不是把长命令直接写在 crontab：
    - 每小时第 15 分钟备份。
    - 随机延迟 0–5 分钟，避免与其他任务同时运行。
    - 使用 `nice`/`ionice` 降低优先级。
  - 本地暂存最多保留 48 小时，并在接近容量阈值时告警，不能静默填满 USB SSD。
  - 保留策略：
    - 树莓派本地暂存：最近 48 份小时备份。
    - 极空间小时备份：最近 7 天。
    - 每日备份：最近 30 天。
    - 每周备份：最近 12 周。
    - 每月备份：最近 12 个月。
  - 批量导题、批量改题、应用升级和数据库迁移前后，提供带说明标签的手动备份入口，不进入普通自动清理范围。
- 影响范围：
  - `deploy/raspberry-pi/docker/`
  - systemd service/timer 模板
  - 树莓派本地暂存目录
  - `/mnt/zspace-xzs-backup` 下的备份文件
- 验证方案：
  - 手动执行一次备份，确认 dump、SHA-256 和 manifest 同时存在。
  - 确认复制后的备份文件与本地暂存文件校验值一致。
  - 构造一个损坏文件，验证脚本不会把它标记为最新可恢复备份。
  - 验证保留规则只清理 `/mnt/zspace-xzs-backup` 下的项目备份目录，不触及 PostgreSQL 数据目录。

### 3. 备份恢复验证

- 当前现状：
  - 当前 Docker 路线已具备隔离恢复演练和破坏性正式恢复双确认门。
  - 真实 NAS 影子备份的隔离恢复已通过；生产首份小时备份对应的恢复报告
    `restore-test-20260727T090623Z-26482.json` 已通过。
  - `xzs-postgres-restore-test.timer` 已启用。
- 判断：
  - `pg_restore --list` 只能证明归档目录可读，不能证明整库可恢复。
  - 必须定期恢复到隔离数据库或临时 PostgreSQL 容器，不能直接覆盖生产库做演练。
- 修改方案：
  - 每周在低峰执行一次自动恢复演练：
    1. 选取极空间最新已验证备份。
    2. 启动临时 PostgreSQL 容器或创建隔离测试库。
    3. 执行完整 `pg_restore`。
    4. 检查 Flyway schema 版本。
    5. 对用户、题目、试卷、答卷、答题明细、错题和纠错记录等关键表校验行数。
    6. 执行只读一致性检查，例如孤立答题记录和缺失外键关系检查。
    7. 输出恢复耗时和验证摘要到 NAS `restore-tests/`。
    8. 删除临时容器或测试库。
  - 正式恢复脚本必须要求：
    - 显式传入目标数据库和备份文件。
    - 显式设置确认变量。
    - 默认拒绝覆盖 production。
    - 恢复前停止应用写入并再生成一份抢救备份。
- 影响范围：
  - Docker 恢复脚本、临时容器、恢复报告。
- 验证方案：
  - 从极空间随机选择一份非最新备份，成功恢复到临时库。
  - 用临时应用连接恢复库，完成学生登录、错题本读取、考试记录读取和管理端查看。
  - 记录真实恢复时间，更新 RTO。

### 4. Neon 异地灾备

> 每日刷新加固与 Neon `test` 数据更新的后续执行拆分见
> `docs/plans/active/2026-08-04-neon-daily-data-refresh-plan.md`。该方案明确区分
> 隔离 DR 刷新与会覆盖测试写入的 `test` branch reset。

- 当前现状：
  - 生产应用已不再连接 Neon production；Neon 旧环境备份和独立停止态
    `xzs-app-neon-rollback` 容器在 7 天观察期内保留。
  - `xzs-neon-dr-refresh.timer` 尚未启用，必须等待本地主库稳定观察至少 7 天、
    DR 专用目标和凭据准备完成，并通过首次人工刷新验证。
  - 排查期间 Neon 凭据曾出现在诊断输出中；生产稳定后必须轮换 Neon production
    密码，并只同步到未来 DR 专用配置，不在本文记录任何凭据。
- 判断：
  - 第一阶段不使用实时逻辑复制，避免家庭网络入站、复制槽、DDL、sequence 和双主切换复杂度。
  - Neon 作为数据库灾备，需要周期性恢复经过验证的本地 dump，而不是只上传备份文件。
- 修改方案：
  - 最终切换前：
    - 在 Neon 保留一个明确命名的切换前恢复点或分支，例如 `pre-local-primary-202607xx`。
    - 记录 Neon production 当前直接连接串，但不打印或提交。
  - 切换后观察期：
    - 前 7 天先保持切换前 Neon 恢复点不变。
    - 树莓派的新写入每小时进入极空间。
    - 若需回退 Neon，先把树莓派最新 dump 恢复到单独的 Neon 灾备目标，再切应用，避免丢失切换后的写入。
  - 稳定后：
    - 每日从“极空间已验证备份”刷新 Neon 灾备数据库。
    - 使用 Neon 直接、非 pooled 连接串执行 `pg_restore`；Neon 官方明确建议 `pg_dump`/迁移不要使用 pooled 连接。
    - 刷新前保留上一恢复点；刷新完成后校验 schema、关键表行数和只读 API。
    - 应用默认不连接 Neon，只有故障切换流程才能改回 Neon。
    - Neon production 密码轮换后，旧连接信息必须失效；未来 DR 刷新只读取专用、
      未提交的配置。
  - Neon 官方资料：
    - 迁移时使用 direct connection：<https://neon.com/docs/connect/connection-pooling>
    - `pg_dump`/`pg_restore` 迁移方式：<https://neon.com/docs/import/migrate-from-neon>
    - Neon branch 与时间点恢复：<https://neon.com/docs/guides/branching-intro>
- 影响范围：
  - Neon production branch/灾备数据库。
  - Neon 直接连接凭据。
  - 灾备刷新脚本和切换说明。
- 验证方案：
  - 用最新 NAS dump 恢复一次 Neon 灾备目标。
  - 用临时应用连接 Neon 灾备目标执行只读烟测。
  - 验证树莓派生产应用仍只连接本地 PostgreSQL。
  - 演练“停止树莓派写入 → 更新 Neon → 修改 datasource → 启动应用 → 验证”的完整过程。
  - 演练后恢复树莓派主库角色，确保没有双边写入。

### 5. Neon 到本地 PostgreSQL 的最终迁移

- 当前现状：
  - 2026-07-27 正式切换已完成，本地 PostgreSQL 18 是当前权威数据源。
  - 正式入口是 `deploy/raspberry-pi/docker/cutover-neon-to-local-postgres.sh`，
    固定 ARM64 应用镜像 tag 为 `986c8aa4`。
  - 首份生产小时备份和隔离恢复已通过；正式生产 5 轮 API 与真实浏览器只读验收
    已通过，核心上线结论为 PASS。
  - 最终 health 为 `UP`，`xzs-app` 和 `xzs-postgres` restart count 均为 `0`；
    独立回滚容器已创建，两个本地 timer active、Neon DR timer inactive；树莓派
    温度 39.9°C 且无降频。
- 判断：
  - 最终切换必须有短暂停写窗口，不能在 dump 后继续向 Neon 写入。
  - 应先做影子恢复和页面性能验证，再执行生产切换。
- 修改方案：
  - 影子演练：
    1. 部署本地 PostgreSQL，但不切换生产应用。
    2. 从 Neon production 的 direct connection 导出自定义格式 dump。
    3. 恢复到树莓派本地库。
    4. 启动第二个只供验收的应用实例，例如监听 `127.0.0.1:18000`。
    5. 对比 Neon 和本地关键表行数、Flyway 版本和页面数据。
    6. 测量登录、错题本、考试记录、答题提交和管理端列表。
  - 正式切换：
    1. 选择低使用时段并公告停写。
    2. 停止生产应用，阻止 Neon 新写入。
    3. 创建 Neon 切换前恢复点。
    4. 导出最终 dump，并生成 SHA-256。
    5. 清空并恢复树莓派本地目标库。
    6. 校验 schema 和关键表行数。
    7. 修改应用 datasource 指向 compose 内的 `postgres`。
    8. 启动应用并执行 API、页面和写入验收。
    9. 开放用户入口。
    10. 立即生成第一份本地备份并复制到极空间。
  - 已实施的正式入口用法：

    ```sh
    sudo ./ops/cutover-neon-to-local-postgres.sh \
      --image crpi-s5bag0a5r8vcgncq.cn-hangzhou.personal.cr.aliyuncs.com/randolph87/gesp-csp-quiz:986c8aa4 \
      --data-dir "<USB-SSD>/xzs" \
      --confirm CUTOVER_NEON_TO_LOCAL \
      --dry-run
    ```

    只读预检通过后去掉 `--dry-run` 执行。只有根文件系统已确认位于 `/dev/sd*`
    或 `/dev/nvme*` USB SSD、且不是 SD/MMC 时才追加 `--allow-root-usb-ssd`。
    脚本拒绝 `latest`，要求明确 tag/digest 和切换确认，并在内部进入正式恢复的
    生产库双确认门。切换阶段失败会恢复旧 Neon 环境并重启回滚容器。
  - Neon dump 的恢复清单只对白名单中的 `pg_session_jwt` `EXTENSION` 和
    `COMMENT` TOC 项做兼容过滤，其他项目不得忽略；普通 PostgreSQL dump 不受影响。
  - 回滚条件：
    - 核心页面无法使用。
    - Flyway 迁移失败。
    - 关键表行数或业务数据不一致。
    - 数据目录不在 USB SSD。
    - 本地数据库延迟异常或发生 I/O 错误。
  - 回滚时必须先停止本地写入；如果本地已经产生新数据，要先导出并恢复到 Neon，不能直接把 datasource 指回旧 Neon 数据。
- 影响范围：
  - 生产写入窗口。
  - Neon production、本地 PostgreSQL 和应用 datasource。
  - Cloudflare 公网入口本身不需要切换。
- 验证方案：
  - 数据库：Flyway 版本和关键表行数一致。
  - API：健康检查、学生登录、老师登录、错题本、考试记录、答题提交、纠错提交和审核。
  - UI：学生和管理端真实浏览器流程，无控制台错误。
  - 持久化：提交一条专用测试数据后重启 PostgreSQL 和应用，数据仍存在。
  - 性能：每个关键操作至少测 5 次，记录中位数和 P95，与切换前树莓派 + Neon 基线对比。
  - 备份：切换后第一份 NAS 备份可恢复到临时库。

### 6. 监控、告警和日常运维

- 当前现状：
  - 当前项目主要有应用健康检查和容器日志，没有本地数据库与备份任务状态监控。
- 判断：
  - 本地数据库把网络延迟问题转化为本地硬件、磁盘、备份和供电责任，必须同步补齐告警。
- 修改方案：
  - 至少监控：
    - PostgreSQL 容器健康状态。
    - USB SSD 使用率、I/O 错误和 SMART 状态。
    - 树莓派温度、内存和 swap。
    - 最近一次成功本地备份时间。
    - 最近一次成功备份复制和校验时间。
    - 最近一次恢复演练时间。
    - 最近一次 Neon 灾备刷新时间。
  - 告警阈值建议：
    - 1 小时备份超过 2 个周期未成功：告警。
    - USB SSD 使用率超过 80%：预警；超过 90%：严重告警。
    - 7 天没有成功恢复演练：预警。
    - 数据库容器连续 3 次健康检查失败：严重告警。
  - 备份日志不得包含数据库密码或 Neon URL。
- 影响范围：
  - 运维脚本、日志和通知渠道。
- 验证方案：
  - 人为停止 PostgreSQL、制造过期状态文件，确认对应告警能触发。
  - 恢复服务后确认告警可以自动解除。

### 7. 当前不实施连续 WAL/PITR

- 当前现状：
  - 用户已确认可以接受不超过 1 小时的数据损失窗口。
- 判断：
  - 对当前规模，小时级完整 dump 更容易部署、验证和恢复。
  - 当前没有必要增加 pgBackRest、连续 WAL、保留和恢复时间线的运维复杂度。
- 修改方案：
  - 本轮不修改 PostgreSQL `wal_level`、`archive_mode` 或 `archive_command`。
  - 本轮不引入 pgBackRest、WAL-G 或逻辑复制。
  - 以每小时 `pg_dump --format=custom`、SHA-256 校验、NAS 历史保留和定期完整恢复演练满足当前目标。
  - 将连续 WAL/PITR 仅保留为未来需求发生变化时的独立方案，不提前建设。
- 影响范围：
  - 当前无额外影响。
- 验证方案：
  - 连续运行至少 24 小时，确认每个小时都能形成一个可校验的恢复点。
  - 从相邻两个小时恢复点分别恢复，证明小时级历史版本可选。

## 推荐执行顺序

1. 已完成：确认生产数据使用 USB SSD bind 路径并设置 PostgreSQL 目录属主
   `999:999`。
2. 已完成：启动本地 PostgreSQL 18 影子库，不切生产。
3. 已完成：从 Neon production 导出并恢复到影子库，完成数据、功能和 5 轮 API
   性能对比；`pg_session_jwt` 使用严格白名单 TOC 过滤。
4. 已完成：实现每小时 dump、校验、原子复制、分层保留和恢复演练。
5. 已完成：真实极空间影子备份和隔离恢复通过。
6. 已完成：2026-07-27 在维护窗口把生产切换到本地 PostgreSQL 18。
7. 进行中：小时备份与隔离恢复 timer 已启用；正式生产 5 轮 API 和真实浏览器只读
   验收已通过，继续观察 7 天并分类 1 条未分类 warning。
8. 待执行：稳定后轮换曾暴露的 Neon production 密码，配置独立 DR 凭据，再启用
   每日 Neon 灾备刷新并完成一次切换演练。
9. 不实施：连续 WAL/PITR 不进入本轮；只有用户将 RPO 要求提高到 10 分钟以内时
   才另写方案。

## 预计实施批次

### 批次 A：本地存储与影子环境准备

- 不改变生产数据库。
- 预计用户中断：0。
- 状态：已完成。
- 产出：SSD 路径、影子 PostgreSQL 和基础性能数据。

### 批次 B：影子 PostgreSQL 与备份链路

- 新增本地数据库但不接生产流量。
- 预计用户中断：0。
- 状态：已完成。
- 产出：影子库、NAS 自动备份、恢复报告和性能基准。

### 批次 C：生产切换

- 停写、最终 dump、恢复和 datasource 切换。
- 当前数据规模下预计维护窗口：30–90 分钟，影子演练后再收窄。
- 状态：2026-07-27 已完成；首份小时备份、隔离恢复报告、正式生产性能与浏览器
  只读验收均通过，核心上线结论为 PASS。
- 产出：本地生产数据库和首份 NAS 备份。

### 批次 D：Neon 灾备

- 切换稳定后执行。
- 预计用户中断：0；灾备演练时需要单独安排维护窗口。
- 状态：待 7 天观察完成；Neon DR timer 当前未启用。
- 产出：每日异地恢复点和故障切换记录。

## 风险与待确认

- 前提：`/mnt/zspace-xzs-backup` 稳定可用、容量充足且可由备份服务写入；NAS 自身配置和运维不在本文范围。
- 已确认：PostgreSQL 生产数据目录使用 USB SSD 显式 bind，且属主为 `999:999`；
  NAS 只保存备份，不保存实时数据目录。
- 已确认：日常数据库备份可以接受不超过 1 小时的数据损失窗口，因此当前使用小时级逻辑备份。
- 待确认：树莓派与极空间同时不可用时，是否可以接受 Neon 最多 24 小时的数据落后；如果也要求不超过 1 小时，需要提高 Neon 刷新频率或增加另一份小时级异地文件备份。
- 待确认：Neon 当前套餐允许的分支、存储和恢复窗口，实施前不假设免费额度足以长期保留多个灾备分支。
- 风险：NAS 与树莓派位于同一地点，不能防范火灾、雷击、盗窃和整屋断电，因此仍需 Neon 异地灾备。
- 风险：本地 PostgreSQL 让树莓派承担生产数据持久化责任，USB SSD、供电和恢复演练成为上线前置条件。
- 风险：项目当前 PostgreSQL JDBC 驱动和 Flyway 版本较旧；本地 PostgreSQL 18 影子验证必须覆盖启动迁移和所有关键查询，不通过则先处理兼容性再切换。
- 风险：正式切换后直接把 datasource 指回旧 Neon 会丢失本地新写入，任何回滚都必须先冻结写入并同步最新数据。
- 风险：排查输出曾暴露 Neon production 凭据。稳定后必须轮换密码，并同步更新未来
  DR 专用配置；旧凭据、完整连接串和新密码均不得写入提交文件、日志或聊天。
- 风险：Neon 恢复所需的 `pg_session_jwt` 兼容处理只能过滤其 `EXTENSION` 和
  `COMMENT` 白名单 TOC 项，不能扩大为忽略其他恢复错误。

## 成功标准

- 已完成：生产应用只写树莓派本地 PostgreSQL。
- 已完成：PostgreSQL 数据位于 USB SSD，不位于 SD 卡或 NAS。
- 已完成：Compose 不映射 PostgreSQL `5432`。
- 观察中：每小时形成备份，极空间最新已验证恢复点不早于当前时间 75 分钟；
  连续两个周期失败必须触发严重告警。
- 已完成首轮：真实 NAS 备份已恢复到隔离数据库并通过关键数据检查；继续由每周
  timer 验证。
- 待执行：Neon 每日拥有经过验证的灾备数据，且默认没有生产应用写入。
- 已完成切换保护：旧 Neon 环境和停止态回滚容器保留，故障切换流程不得产生双主。
- 已完成：正式生产关键页面每项 5 轮 API 有中位数/P95与基线改善记录；Playwright
  首页、错题本翻页和考试记录只读流程通过，控制台 `0 errors`。保留 1 条未分类
  warning 在观察期内继续处理。

## 收尾记录

- 完成状态：核心上线验收 PASS；7 天观察、warning 分类与 Neon DR 批次未完成，
  计划保持 active。
- 归档日期：
- 归档原因：观察期、正式生产验收、凭据轮换和 Neon DR 验证完成后再填写。

### 涉及文件

- `docker/docker-compose.yml`
- `docker/.env.production.example`
- `docker/.env.shadow.example`
- `deploy/raspberry-pi/docker/`
- `scripts/sync-raspi-production-env.ps1`
- `docs/container-image-deployment.md`
- `docker/README.md`
- `docs/project-structure/database-deploy.md`

### 实施记录

- 2026-07-27：完成可部署候选资产。Compose 新增 PostgreSQL 18.4、USB SSD 显式
  bind、内部健康依赖且不映射 `5432`；应用 datasource 改为 Compose 内部数据库。
- 2026-07-27：新增小时 custom dump、归档可读校验、SHA-256、manifest、NAS
  `.partial` 原子发布、项目目录限定保留、手动备份和最后成功状态资产。
- 2026-07-27：新增隔离恢复演练、正式恢复双重确认门、专用 Neon DR 刷新脚本，
  以及小时备份、每周恢复演练和每日 Neon DR 刷新的 systemd 模板。
- 2026-07-27：补充固定 `xzs-shadow` project 的影子 PostgreSQL 与影子应用入口。
  影子环境使用独立容器、网络、日志和 USB SSD 数据目录，只绑定
  `127.0.0.1:18000`；准备脚本仅恢复 archive、SHA-256 和 manifest 均通过的 dump，
  再启动当前应用镜像验证 JDBC、Flyway 和健康接口。默认清理保留影子数据，删除需显式确认。
- 2026-07-27：同步脚本新增 `-ShadowAssetsOnly`。该模式不接触生产 `.env`，
  只同步 Compose、影子 env 模板和 ops，并以无 secret 占位配置检查生产与影子
  Compose；与任何生产重启或验证参数组合时前置拒绝。
- 2026-07-27：同一 `Dockerfile` 构建的 Fly release v15 在 Neon `test` 环境通过
  测试；树莓派候选固定为 ARM64 镜像 tag `986c8aa4`。
- 2026-07-27：Neon production dump 已成功恢复到影子 PostgreSQL 18。Neon 专属
  `pg_session_jwt` 只过滤白名单内的 `EXTENSION` 和 `COMMENT` TOC 项；影子功能、
  每项 5 轮 API、真实极空间影子备份和隔离恢复均通过。
- 2026-07-27：正式运行 `cutover-neon-to-local-postgres.sh`，生产切换到本地
  PostgreSQL 18 成功。入口要求 `--dry-run` 预检、固定 tag/digest、明确确认；
  根文件系统作为 USB SSD 时另需 `--allow-root-usb-ssd`，并保留失败自动回滚。
- 2026-07-27：首份小时备份 `xzs-20260727T090616Z.dump` 和隔离恢复报告
  `restore-test-20260727T090623Z-26482.json` 通过；小时备份和每周恢复演练 timer
  已启用，Neon DR timer 未启用。
- 2026-07-27：旧 Neon 环境备份和独立停止态 `xzs-app-neon-rollback` 容器继续
  保留。最终 health 为 `UP`，应用与 PostgreSQL restart count 均为 `0`；两个本地
  timer active、Neon DR timer inactive；树莓派温度 39.9°C 且无降频。
- 2026-07-27：正式公网生产每项 5 次测量完成，四个场景中位数分别为 742.9、
  1090.1、729.0、748.7 ms，相对 Neon 基线改善 72.0%–74.8%。Playwright 首页、
  错题本翻页和考试记录只读流程通过，未产生写入，控制台 `0 errors`、`1` 条
  未分类 warning。核心上线验收 PASS，计划保持 active 至至少 7 天稳定观察完成。
- 观察期收尾待办：轮换排查中曾暴露的 Neon production 密码，并只同步到未来 DR
  专用配置；不得在实施记录中写入真实凭据。
