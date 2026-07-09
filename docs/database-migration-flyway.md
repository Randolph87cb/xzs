# Flyway 数据库迁移说明

## 目标

后端从阶段 4 开始引入 Flyway 管理 PostgreSQL schema 迁移。当前阶段只建立基线迁移能力，不修改业务表结构。

基线迁移文件为：

- `source/xzs/src/main/resources/db/migration/V1__baseline_schema.sql`

该文件内容来自现有 `sql/xzs-postgresql.sql`，用于空库初始化。

## 配置策略

通用配置位于 `source/xzs/src/main/resources/application.yml`：

- `spring.flyway.enabled` 默认启用，可通过 `SPRING_FLYWAY_ENABLED=false` 临时关闭。
- `spring.flyway.locations` 使用 `classpath:db/migration`。
- `spring.flyway.baseline-on-migrate` 默认启用，可通过 `SPRING_FLYWAY_BASELINE_ON_MIGRATE=false` 覆盖。
- `spring.flyway.baseline-version` 固定为 `1`。
- `spring.flyway.validate-on-migrate` 启用，迁移校验失败时应用启动失败。
- `spring.flyway.clean-disabled` 启用，避免误执行清库操作。

`application-prod.yml` 继续使用现有 `SPRING_DATASOURCE_URL`、`SPRING_DATASOURCE_USERNAME`、`SPRING_DATASOURCE_PASSWORD` 环境变量，不需要为 Flyway 另配 datasource。

## 空库初始化

新建空 PostgreSQL 数据库后，正常启动后端应用即可。Flyway 会创建 `flyway_schema_history` 表并执行 `V1__baseline_schema.sql`。

空库初始化适用于全新本地开发库、全新测试库和首次部署的空生产库。

## 已有库接入

已有非空数据库接入 Flyway 前必须先备份。首次启动时，`baseline-on-migrate=true` 会在检测到非空 schema 且没有 `flyway_schema_history` 时写入版本 `1` 的基线记录，避免直接重放 `V1__baseline_schema.sql` 导致对象已存在或覆盖风险。

接入前建议确认：

- 数据库 schema 与当前 `sql/xzs-postgresql.sql` 对应的业务结构一致。
- 应用连接的数据库、schema 和账号与实际运行环境一致。
- 已完成可恢复备份，并记录备份文件位置。
- 首次接入后检查 `flyway_schema_history` 中存在版本 `1` 的 baseline 记录。

## 备份要求

生产库或长期使用的测试库接入前，必须先执行 PostgreSQL 逻辑备份或平台快照备份。备份需要覆盖 schema、数据、序列值和权限。

推荐至少保留：

- 接入前完整备份。
- 首次 Flyway 启动日志。
- `flyway_schema_history` 查询结果。

## 失败处理

迁移失败时应用启动应失败，不应跳过错误继续运行。

处理步骤：

1. 停止应用，保留完整启动日志。
2. 不要手工修改已执行迁移文件。
3. 检查数据库是否已经部分执行迁移；PostgreSQL 通常在事务内回滚可回滚 DDL，但仍需人工确认。
4. 如生产库受影响，优先使用接入前备份恢复，再分析失败原因。
5. 修复方式应新增后续迁移文件，除非该迁移从未进入任何共享环境。

## 后续迁移命名规范

后续业务 schema 变更必须新增迁移文件，不再直接修改 `V1__baseline_schema.sql`。

命名格式：

```text
V{递增版本号}__{英文小写描述}.sql
```

示例：

```text
V2__add_question_review_columns.sql
V3__create_exam_audit_table.sql
```

约定：

- 版本号单调递增，不复用已发布版本号。
- 描述使用英文小写、数字和下划线。
- 一个迁移文件只表达一组相关 schema 变化。
- 已合入共享分支或部署过的迁移文件不得改写；需要修正时新增下一版迁移。
