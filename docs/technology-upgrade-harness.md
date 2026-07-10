# 技术架构升级 Harness

## 目标

在不重写业务功能的前提下，分阶段升级信息学客观题一本通的运行架构、后端依赖、部署可靠性和树莓派自托管能力。每个阶段都必须有明确实现范围和独立验证结果，避免把后端大版本升级、部署脚本、数据库迁移和业务功能混在一次改动里。

## 适用范围

适用于以下工作：

- Spring Boot、Spring Security、Undertow、PostgreSQL JDBC、Maven Wrapper 等后端运行栈升级。
- 树莓派、Docker、systemd、健康检查、数据库备份恢复等部署能力。
- Flyway 或同类数据库迁移工具的引入。
- 构建、启动、远程验收、资源占用基线脚本。

不适用于以下工作：

- 班级管理、智能训练、题目审核、题库导入等业务功能改造。
- 前端视觉重做或交互大改。
- 微信小程序功能迁移。
- 未经单独评估的一步式 Spring Boot 3/4 大版本迁移。

## 输入

开始前需要确认：

- 当前仓库工作区状态，不能覆盖用户已有改动。
- 目标运行环境：默认兼容 Windows 开发机、Linux 服务器和树莓派 64 位系统。
- 数据库目标：默认 PostgreSQL，先保持现有 schema，不在架构升级阶段改业务表。
- 构建入口：优先使用 `scripts/build-all.ps1`、`scripts/package-backend.ps1`、`source/xzs/mvnw.cmd`。
- 部署入口：现有 `Dockerfile`、`fly.toml`、`start.ps1`，后续新增树莓派部署文件。

## 执行流程

所有阶段串行推进。每个阶段内部至少拆成两个 subagent：

- 实现 subagent：只负责该阶段代码、配置、脚本或文档改动。
- 验证 subagent：只负责读取实现结果并运行验证，不能修复实现问题；验证失败时返回具体失败点。

如果某阶段工作量较大，应继续拆分多个实现 subagent，但每个 subagent 的写入范围必须互不重叠。验证仍由独立 subagent 完成。

### 阶段 0：文档与执行结构

目标：

- 固化本 harness。
- 明确阶段、范围、检查点和失败处理。

检查点：

- `docs/technology-upgrade-harness.md` 存在。
- 文档包含目标、适用范围、输入、执行流程、角色分工、检查点、产出、失败处理和 Git 策略。

### 阶段 1：树莓派运行参数与健康检查

目标：

- 让当前 Spring Boot 2.1 版本在树莓派上更容易稳定运行。
- 增加最小健康检查能力，供 systemd、Docker 和部署脚本判断服务是否可用。

实现范围：

- 后端 `pom.xml` 增加 Spring Boot Actuator。
- `application.yml` 将 Undertow 线程、buffer、direct buffer 和 Hikari 连接池参数改为环境变量可配置。
- `application-prod.yml` 保持 datasource 环境变量兼容。
- 新增或更新树莓派部署文档，记录推荐 JVM、Undertow、Hikari 参数。

验证范围：

- Maven package 或至少后端编译通过。
- 确认配置文件能被 Spring Boot 2.1 识别。
- 如可启动，检查 `/actuator/health` 可访问。

### 阶段 2：树莓派部署资产

目标：

- 补齐可复制到树莓派上的运行服务、数据库初始化和备份恢复脚本。

实现范围：

- 新增 `deploy/raspberry-pi/xzs.service` systemd 模板。
- 新增 `deploy/raspberry-pi/init-db.sh`。
- 新增 `deploy/raspberry-pi/backup-db.sh`。
- 新增 `deploy/raspberry-pi/restore-db.sh`。
- 新增或完善 `docs/raspberry-pi-deployment.md`。

验证范围：

- Shell 脚本通过 `bash -n`。
- systemd 模板变量、路径和环境变量与文档一致。
- 文档中的命令与文件名一致。

### 阶段 3：安全小版本升级

目标：

- 在尽量不改变 Java 基线的情况下，把后端从 Spring Boot 2.1.6 升级到 Spring Boot 2.7.x，并升级 PostgreSQL JDBC 驱动。

实现范围：

- `source/xzs/pom.xml`。
- 只做必要兼容修复，不改业务逻辑。
- 如 Spring Security 配置或依赖 API 发生变化，只做最小适配。

验证范围：

- `mvn -DskipTests package` 通过。
- 如有测试，执行后端测试。
- 本地启动能够连接 PostgreSQL。
- 管理端和学生端静态入口仍能访问。

### 阶段 4：数据库迁移工具

目标：

- 引入 Flyway，后续业务表变更不再只依赖初始化 SQL。

实现范围：

- 增加 Flyway 依赖与配置。
- 将现有 PostgreSQL 初始化脚本整理为基线迁移，或采用 baseline-on-migrate 路线。
- 记录生产库接入迁移工具前的备份要求。

验证范围：

- 空库可以初始化。
- 已有库可以 baseline 后启动。
- 迁移失败时应用明确失败，不静默跳过。

### 阶段 5：Java 17 与 Spring Boot 3 预研

目标：

- 单独评估 Java 17 和 Spring Boot 3 的破坏性，不直接合入主线大改。

实现范围：

- 允许在临时分支或临时文档中记录改动清单。
- 重点识别 `javax.* -> jakarta.*`、Spring Security、MyBatis、PageHelper、Undertow 和测试依赖的迁移风险。

验证范围：

- 输出评估报告。
- 不要求一次完成生产可用升级。

## 角色分工

- 主线程：维护 harness 文档、拆阶段、创建 subagent、整合结果、决定是否进入下一阶段。
- 实现 subagent：按指定文件范围修改，不提交 Git，不 push，不处理验证任务。
- 验证 subagent：只验证实现结果，不修复代码，不提交 Git，不 push。
- 脚本：用于构建、启动、静态资源同步、数据库备份恢复和远程验收。

## 检查点

每个阶段完成后必须至少给出：

- 修改文件列表。
- 执行过的验证命令。
- 验证结果。
- 未验证或失败内容。
- 是否建议进入下一阶段。

## 产出

最终产出包括：

- 技术升级 harness 文档。
- 树莓派部署文档和部署资产。
- 可配置的低资源运行参数。
- 健康检查端点。
- 后端安全小版本升级记录。
- 数据库迁移工具接入方案和实施结果。
- 每阶段验证记录。

## 失败处理

- 信息不足：停止当前阶段，列出缺失信息，不猜测生产环境。
- 实现失败：实现 subagent 返回失败原因，主线程决定缩小范围或拆分更多 subagent。
- 验证失败：验证 subagent 返回失败命令、日志摘要和可能原因；修复必须重新交给实现 subagent。
- 依赖升级冲突：优先回退到上一阶段稳定状态，不顺手改业务逻辑。
- 树莓派资源不足：优先降低 JVM、Undertow、Hikari 参数，不改业务代码绕过问题。

## Git 策略

- subagent 不提交 Git、不 push。
- 主线程在每个阶段验证通过后再统一决定是否提交。
- 如果用户没有另行要求，完成一个稳定阶段后按项目规则使用中文提交信息并 push。
- Git 命令串行执行，不并发运行。
