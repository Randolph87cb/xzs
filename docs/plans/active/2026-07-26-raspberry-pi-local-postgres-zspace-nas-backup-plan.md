# 树莓派本地 PostgreSQL、极空间 NAS 备份与 Neon 灾备方案

状态：active
创建日期：2026-07-26
完成日期：
验证摘要：2026-07-27 已完成树莓派 NAS 挂载只读检查：CIFS/SMB 3.0 挂载和局域网连通正常，fstab 无解析错误，凭据文件权限合格；发现 systemd 尚未重新加载最新 fstab、缺少 automount/短超时、挂载文件权限过宽、普通用户不可写，以及 NAS 使用率已达 86%。相关整改和验收项已纳入本文。

## 背景与现状

- 当前生产应用部署在树莓派，使用 Docker Compose 运行 `xzs-app`，生产目录是 `/opt/apps/gesp-csp-quiz`。
- 当前生产应用连接 Neon `production` branch；Fly.io 和本地开发连接 Neon `test` branch。
- 已确认树莓派是 `aarch64`，有约 8 GB 内存，温度、负载和降频状态正常；系统存在约 439 GB 的 `/dev/sda2` 外接存储，但正式实施前仍需确认其实际挂载点、文件系统和是否为 USB 3 SSD。
- 已测得树莓派访问 Neon 的简单数据库往返中位数约为 232 ms，而树莓派本机静态请求约为 6 ms。错题本等页面包含多次鉴权和业务 SQL，跨区域数据库往返会连续叠加。
- 极空间 NAS 已通过 CIFS/SMB 3.0 挂载到树莓派 `/mnt/zspace-xzs-backup`，NAS 使用局域网地址并通过有线网络访问；2026-07-27 实测平均往返约 1.23 ms、0% 丢包，挂载可读且目录访问正常。
- 当前 NAS 挂载使用 `/etc/zspace_credentials`，文件权限为 `0600 root:root`，凭据未写入 fstab，配置正确。
- 当前 fstab 已配置 `nofail`，但缺少 `_netdev`、`x-systemd.automount` 和短挂载超时；systemd 提示 fstab 已修改但尚未 `daemon-reload`，当前 mount unit 超时仍为 90 秒。
- 当前 CIFS 挂载隐式使用 `uid=0,gid=0,file_mode=0755,dir_mode=0755`：`caobin` 不能写入，且备份文件会对本机其他用户可读并显示为可执行。后续备份任务应固定由 root systemd service 执行，并把文件/目录权限收紧。
- 极空间当前总容量约 7.3 TB、已使用约 6.3 TB、剩余约 1.1 TB，使用率 86%；容量足够当前数据库，但已经超过方案的 80% 预警线。
- 极空间具体型号、存储池模式、快照和 UPS 能力尚未确认。
- 项目内已有旧的本机 PostgreSQL `pg_dump`/`pg_restore` 脚本，但它们对应历史 systemd/Jar 路线，不能直接套用到当前 Docker Compose 生产部署。
- 当前 `docker/docker-compose.yml` 只有应用容器，没有本地 PostgreSQL、备份任务、备份目录和 NAS 挂载。
- 当前 Neon production 使用 PostgreSQL 18.4。树莓派本地 PostgreSQL 应优先保持相同主版本，并在实施时固定具体镜像版本或 digest，避免使用不受控的浮动大版本。

## 结论

推荐把树莓派 USB SSD 上的 PostgreSQL 作为唯一生产主库，极空间作为本地异机备份文件库，Neon production 作为异地冷灾备；当前已确认可以接受不超过 1 小时的数据损失窗口，因此采用“每小时逻辑备份到极空间 + 每日刷新 Neon”的简单可靠路线，不把连续 WAL/PITR 纳入本轮实施。

不建议：

- 不把 PostgreSQL 实时数据目录放在极空间的 NFS/SMB 共享目录。
- 不让应用同时写树莓派和 Neon。
- 不直接把未验证的 dump 覆盖到 Neon。
- 不把 NAS RAID、文件同步或 Neon 当前数据副本单独当成完整备份。
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
| 误删或错误批量修改 | 极空间历史备份/快照 | 1 小时到指定历史版本 | 30–90 分钟 | 不使用最新副本覆盖历史 |

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

## 需求拆解

### 1. 极空间备份空间准备

- 当前现状：
  - 已确认极空间共享目录通过 CIFS/SMB 3.0 挂载到 `/mnt/zspace-xzs-backup`。
  - 已确认 NAS 位于树莓派同一局域网，实测平均约 1.23 ms、0% 丢包。
  - 已确认挂载目录可读、目录访问无超时；当前 `caobin` 用户不可写。
  - 已确认 fstab 无解析错误，凭据文件 `/etc/zspace_credentials` 为 `0600 root:root`。
  - 已确认 fstab 修改后尚未执行 `systemctl daemon-reload`。
  - 已确认当前没有 systemd automount 单元，mount unit 默认超时为 90 秒；NAS 离线时虽有 `nofail`，仍可能拖慢开机或路径访问。
  - 已确认挂载文件和目录模式均为 `0755`，不适合保存包含生产数据的数据库备份。
  - 已确认 NAS 使用率为 86%，约剩余 1.1 TB。
  - 未确认型号、存储池模式、快照能力和 UPS。
- 判断：
  - 极空间适合保存数据库备份文件和历史快照。
  - PostgreSQL 的 `PGDATA` 必须留在树莓派本地 USB SSD；NAS 仅接收已经生成完成且校验过的备份文件。
  - 当前 SMB 3.0 链路性能足够用于小时级备份，不需要为了本轮迁移切换 NFS。
  - `nofail` 可以避免挂载失败直接导致系统启动失败，但不能消除默认 90 秒等待；应增加 systemd automount 和短超时。
  - 普通用户不可写不是阻塞项：数据库备份应由 root systemd service 执行。真正需要修正的是 `0755` 导致本机其他用户可读和文件可执行。
  - 86% 使用率已经进入容量预警区，实施自动保留策略和容量告警前不能把 NAS 备份视为无人值守完成。
  - 极空间不同型号提供的快照能力可能不同，实施前仍需在管理界面确认，不能假定当前设备一定支持全部快照功能。
- 修改方案：
  - 在极空间创建独立共享目录，推荐使用纯英文路径：

    ```text
    xzs-production-backup/
      incoming/
      hourly/
      daily/
      weekly/
      monthly/
      manifests/
      restore-tests/
      logs/
    ```

  - 创建独立账号 `xzs-backup`：
    - 只允许访问上述共享目录。
    - 不授予管理员权限。
    - 不允许访问照片、影音和其他私人目录。
  - 当前继续使用已验证的 SMB 3.0，不在本轮额外切换 NFS；不使用极空间公网映射作为日常备份通道。
  - 保留当前挂载点 `/mnt/zspace-xzs-backup` 和凭据文件 `/etc/zspace_credentials`。
  - 将 fstab 挂载选项调整为：

    ```text
    credentials=/etc/zspace_credentials,iocharset=utf8,vers=3.0,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=10s,uid=0,gid=0,file_mode=0600,dir_mode=0700,nosuid,nodev,noexec
    ```

  - 修改 fstab 后执行 `sudo systemctl daemon-reload`，确认生成并启动 `mnt-zspace\x2dxzs\x2dbackup.automount`；不要只依赖重启后自动读取。
  - 备份任务固定使用 root systemd service，普通 `caobin` 用户不需要直接写 NAS；如未来改为非 root 服务，再单独建立最小权限备份组，不把目录放宽为 `0777`。
  - NAS 关机或断网时：
    - 树莓派启动不能等待超过设定的 10 秒挂载超时。
    - PostgreSQL 和 `xzs-app` 必须照常启动。
    - 备份文件留在 USB SSD staging，NAS 恢复后补传。
  - 容量管理：
    - 当前 86% 使用率立即记为预警状态。
    - 在极空间为备份目录设置配额或容量预算，避免与照片、影音等数据无限争用空间。
    - NAS 使用率超过 90% 时触发严重告警并暂停非必要历史副本扩张，但不能删除受保护的手工备份。
    - 实施每小时备份前先用真实 production dump 测量单份大小，据此复核 7 天小时备份、30 天每日备份、12 周周备份和 12 个月月备份的总空间。
  - 如果当前极空间型号支持文件快照：
    - 每日快照保留 30 份。
    - 每周快照保留 12 份。
    - 每月快照保留 12 份。
    - 备份账号不能删除快照。
  - 如果当前型号不支持快照，使用备份脚本的分层保留目录，并考虑让极空间备份中心再复制一份到受支持的云盘。
- 影响范围：
  - 极空间存储池、共享目录、专用账号和局域网协议。
  - 树莓派 `/etc/fstab` 或 systemd mount/automount 单元。
- 验证方案：
  - `findmnt --verify --tab-file /etc/fstab` 为 0 个解析错误，且不再提示 systemd 仍使用旧 fstab。
  - `systemctl show mnt-zspace\x2dxzs\x2dbackup.automount` 显示 `LoadState=loaded`、`ActiveState=active`。
  - 首次访问 `/mnt/zspace-xzs-backup` 能在 10 秒内触发挂载。
  - 树莓派重启时 NAS 在线，首次访问能自动建立挂载。
  - NAS 关机后树莓派重启，PostgreSQL 和应用仍能正常启动，启动过程不因 NAS 等待 90 秒。
  - NAS 恢复后挂载自动恢复，积压备份能够补传。
  - root 备份服务能创建临时文件、校验后原子改名并清理测试文件；`caobin` 和无关本地用户不能写入。
  - 新生成的备份文件模式为 `0600`，目录模式为 `0700`，挂载具有 `nosuid,nodev,noexec`。
  - 凭据文件继续保持 `0600 root:root`，fstab、日志和仓库不包含 NAS 密码。
  - 记录真实 dump 大小，证明当前剩余空间能覆盖保留策略；配置 80% 预警和 90% 严重告警。
  - 使用备份账号只能读写指定目录，不能访问其他目录或管理快照。
  - 在极空间上删除一个测试文件，再通过快照恢复该文件。

### 2. 树莓派本地 PostgreSQL Docker 服务

- 当前现状：
  - 当前 compose 只有 `xzs-app`，应用通过 `SPRING_DATASOURCE_URL` 访问 Neon production。
  - PostgreSQL 实时数据还不在树莓派。
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

### 3. 每小时备份到极空间

- 当前现状：
  - 旧 `deploy/raspberry-pi/backup-db.sh` 面向 systemd/Jar 部署，并假设宿主机安装 PostgreSQL 客户端。
  - 当前 Docker Compose 路线没有可直接使用的备份任务。
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
  - NAS 不可用时：
    - 备份保留在本地暂存。
    - 标记“待同步”并下次重试。
    - 不影响 PostgreSQL 和应用继续运行。
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
  - 极空间备份目录和容量
- 验证方案：
  - 手动执行一次备份，确认 dump、SHA-256 和 manifest 同时存在。
  - 备份过程中断开 NAS，确认应用不受影响且本地保留待同步文件。
  - 恢复 NAS 后确认自动补传且校验值一致。
  - 构造一个损坏文件，验证脚本不会把它标记为最新可恢复备份。
  - 验证保留规则只清理目标备份目录，不触及 PostgreSQL 数据目录或其他 NAS 文件。

### 4. 备份恢复验证

- 当前现状：
  - 现有恢复脚本只执行 `pg_restore`，没有围绕当前 Docker 生产环境的自动验证和恢复演练。
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

### 5. Neon 异地灾备

- 当前现状：
  - Neon production 目前是生产主库。
  - 切换后 Neon production 不再处于日常请求链路。
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

### 6. Neon 到本地 PostgreSQL 的最终迁移

- 当前现状：
  - Neon production 是当前权威数据源。
  - 应用仍可能持续产生登录、答题、纠错和后台更新数据。
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

### 7. 监控、告警和日常运维

- 当前现状：
  - 当前项目主要有应用健康检查和容器日志，没有本地数据库与 NAS 备份状态监控。
- 判断：
  - 本地数据库把网络延迟问题转化为本地硬件、磁盘、备份和供电责任，必须同步补齐告警。
- 修改方案：
  - 至少监控：
    - PostgreSQL 容器健康状态。
    - USB SSD 使用率、I/O 错误和 SMART 状态。
    - 树莓派温度、内存和 swap。
    - NAS 挂载是否可用。
    - 最近一次成功本地备份时间。
    - 最近一次成功 NAS 校验时间。
    - 最近一次恢复演练时间。
    - 最近一次 Neon 灾备刷新时间。
  - 告警阈值建议：
    - 1 小时备份超过 2 个周期未成功：告警。
    - USB SSD 或 NAS 使用率超过 80%：预警；超过 90%：严重告警。
    - 7 天没有成功恢复演练：预警。
    - 数据库容器连续 3 次健康检查失败：严重告警。
  - 备份日志不得包含数据库密码、Neon URL 或 NAS 密码。
- 影响范围：
  - 运维脚本、日志和通知渠道。
- 验证方案：
  - 人为停止 NAS、停止 PostgreSQL、制造过期状态文件，确认对应告警能触发。
  - 恢复服务后确认告警可以自动解除。

### 8. 当前不实施连续 WAL/PITR

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

1. 保留已验证的 SMB 3.0 和 `/mnt/zspace-xzs-backup`，修正 fstab 的 automount、10 秒超时和 root-only 权限，并执行 `systemctl daemon-reload`。
2. 完成 NAS 在线首次访问、NAS 离线开机、NAS 恢复补挂载和 root 写入测试，确认应用不依赖 NAS 启动。
3. 确认极空间型号、存储池模式、快照和 UPS，并针对当前 86% 使用率设置配额、80% 预警和 90% 严重告警。
4. 确认树莓派 `/dev/sda2` 的挂载点、文件系统、USB 3 连接和 SMART 状态。
5. 修改 compose，启动本地 PostgreSQL 影子库，不切生产。
6. 从 Neon production 导出并恢复到影子库，进行数据、功能和性能对比。
7. 实现每小时 dump、校验、NAS 原子复制、分层保留和恢复演练。
8. 确认第一份 NAS 备份可以完整恢复。
9. 在维护窗口执行 Neon 到本地 PostgreSQL 的最终切换。
10. 切换后立即备份到极空间，并观察 7 天。
11. 稳定后启用每日 Neon 灾备刷新，完成一次切换演练。
12. 连续 WAL/PITR 不进入本轮；只有用户将 RPO 要求提高到 10 分钟以内时才另写方案。

## 预计实施批次

### 批次 A：只读确认与 NAS 准备

- 不改变生产数据库。
- 预计用户中断：0。
- 产出：NAS 连接参数、SSD 路径、权限和快照配置。

### 批次 B：影子 PostgreSQL 与备份链路

- 新增本地数据库但不接生产流量。
- 预计用户中断：0。
- 产出：影子库、NAS 自动备份、恢复报告和性能基准。

### 批次 C：生产切换

- 停写、最终 dump、恢复和 datasource 切换。
- 当前数据规模下预计维护窗口：30–90 分钟，影子演练后再收窄。
- 产出：本地生产数据库和首份 NAS 备份。

### 批次 D：Neon 灾备

- 切换稳定后执行。
- 预计用户中断：0；灾备演练时需要单独安排维护窗口。
- 产出：每日异地恢复点和故障切换记录。

## 风险与待确认

- 待确认：极空间具体型号和系统版本。
- 待确认：极空间存储池采用单盘、ZDR、RAID1、RAID5 或其他模式。
- 已确认：当前使用 CIFS/SMB 3.0，局域网实测约 1.23 ms、0% 丢包，本轮无需切换 NFS。
- 待确认：极空间是否支持文件快照、快照保留策略和 UPS 联动。
- 已确认：极空间已通过固定局域网地址挂载到 `/mnt/zspace-xzs-backup`，当前约剩余 1.1 TB，但总使用率已达 86%。
- 已确认：fstab 当前只有 `nofail`，尚缺 `_netdev`、automount 和短超时；systemd 仍使用旧版本生成配置，整改前 NAS 离线可能带来最长约 90 秒等待。
- 已确认：凭据文件为 `0600 root:root`，但挂载文件和目录模式为 `0755`，需要收紧为 root-only 并增加 `nosuid,nodev,noexec`。
- 已确认：`caobin` 当前不能写 NAS；本方案决定由 root systemd service 执行备份，不通过放宽目录权限解决。
- 待确认：树莓派 `/dev/sda2` 的实际挂载点、文件系统和 SMART 健康状态。
- 已确认：日常数据库备份可以接受不超过 1 小时的数据损失窗口，因此当前使用小时级逻辑备份。
- 待确认：树莓派与极空间同时不可用时，是否可以接受 Neon 最多 24 小时的数据落后；如果也要求不超过 1 小时，需要提高 Neon 刷新频率或增加另一份小时级异地文件备份。
- 待确认：Neon 当前套餐允许的分支、存储和恢复窗口，实施前不假设免费额度足以长期保留多个灾备分支。
- 风险：NAS 与树莓派位于同一地点，不能防范火灾、雷击、盗窃和整屋断电，因此仍需 Neon 异地灾备。
- 风险：RAID/ZDR 解决硬盘故障，不解决误删、数据库逻辑损坏和勒索软件，必须保留多时间点备份或快照。
- 风险：NAS 离线时，如果脚本直接依赖 NAS，可能影响备份甚至系统启动；方案要求本地暂存、`nofail` 和自动重试。
- 风险：当前 NAS 使用率已经达到 86%；如果不先配置容量预警和保留策略，自动小时备份可能在长期运行后失败。
- 风险：fstab 修改后未执行 `systemctl daemon-reload`，当前 systemd 单元可能不反映磁盘上的最新配置。
- 风险：当前 CIFS `file_mode=0755,dir_mode=0755` 会让生产备份对无关本地用户可读，且文件显示为可执行。
- 风险：本地 PostgreSQL 让树莓派承担生产数据持久化责任，USB SSD、供电和恢复演练成为上线前置条件。
- 风险：项目当前 PostgreSQL JDBC 驱动和 Flyway 版本较旧；本地 PostgreSQL 18 影子验证必须覆盖启动迁移和所有关键查询，不通过则先处理兼容性再切换。
- 风险：正式切换后直接把 datasource 指回旧 Neon 会丢失本地新写入，任何回滚都必须先冻结写入并同步最新数据。

## 成功标准

- 生产应用只写树莓派本地 PostgreSQL。
- PostgreSQL 数据位于 USB SSD，不位于 SD 卡或 NAS。
- 公网和局域网普通客户端无法访问 PostgreSQL `5432`。
- NAS 使用 systemd automount 和不超过 10 秒的挂载超时；NAS 离线时树莓派、PostgreSQL 和应用能正常启动。
- NAS 凭据保持 `0600 root:root`，备份文件和目录分别为 `0600`、`0700`，并启用 `nosuid,nodev,noexec`。
- NAS 80% 容量预警和 90% 严重告警生效；当前 86% 状态能够触发预警。
- 正常状态下每小时都形成一个备份，极空间最新已验证恢复点不早于当前时间 75 分钟；连续两个周期失败必须触发严重告警。
- 任意抽取一份 NAS 备份可以恢复到隔离数据库，并通过关键数据检查。
- Neon 每日拥有经过验证的灾备数据，且默认没有生产应用写入。
- 故障切换流程不会产生双主。
- 错题本、考试记录等关键页面达到影子环境测得的目标区间，并有改前改后中位数/P95记录。

## 收尾记录

- 完成状态：
- 归档日期：
- 归档原因：
