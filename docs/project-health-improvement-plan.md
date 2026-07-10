# 项目工程健康改进计划

## 背景

本计划用于固化 2026-07-10 对当前仓库工程健康状况的审查结论，并把后续改进拆成可验证、可分派的阶段任务。当前基线 commit 为 `4a306362`。

本文件只记录审查发现和建议，不表示相关代码、配置或发布流程已经完成改造。后续涉及代码或配置变更时，应按 harness 约束交给 subagent 执行；主线程负责审查、验证和统一 Git 提交处理。

## 审查命令摘要

本次审查主要使用以下命令确认仓库事实：

- `git rev-parse --short=8 HEAD`：确认基线提交为 `4a306362`。
- `git status --short`：确认开始写文档前工作区状态。
- `Select-String -LiteralPath source/xzs/pom.xml -Pattern '<skipTests>true</skipTests>'`：确认后端 Maven 默认跳过测试。
- `Select-String -LiteralPath Dockerfile -Pattern 'DskipTests|mvn'`：确认镜像构建使用 `mvn -DskipTests package`。
- `Test-Path -LiteralPath .github/workflows`：确认当前没有 GitHub Actions 工作流目录。
- `Select-String -LiteralPath docs/guide/develop.html,docs/guide/video.html,sql/README.md -Pattern 'MySQL|Node16|Node 16|SQL|下载|download|mysql|node16'`：确认历史静态文档中仍有旧说明。
- `git ls-files 'release/web/**' | Measure-Object`、`Get-ChildItem -LiteralPath release/java -File`：确认发布制品仍被跟踪。
- `(Get-Content -LiteralPath source/xzs/src/main/java/com/mindskip/xzs/service/impl/ExamPaperServiceImpl.java).Count` 与 `Select-String`：确认业务聚合热点规模和职责分布。

## 主要发现

### P1：缺少 CI，后端测试默认被跳过

证据：

- `source/xzs/pom.xml` 中存在 `<skipTests>true</skipTests>`。
- `Dockerfile` 中使用 `mvn -DskipTests package` 构建后端。
- 当前仓库没有 `.github/workflows` 目录。

影响：

- 默认构建路径不会暴露后端测试失败。
- Docker/Fly 构建能生成包，但不能证明后端测试和前端构建链路可重复通过。
- 多协作者并行修改时，缺少统一入口来阻止基础回归进入主分支。

建议：

- 增加 `scripts/verify-all.ps1`，串联后端测试、前端构建、静态资源一致性检查和必要的发布检查。
- 增加 GitHub Actions，至少覆盖 `source/xzs` Maven 测试与 `frontend` 工作区安装/构建。
- 调整跳过测试策略：本地快速打包可以保留显式跳过入口，但 CI 和正式发布路径应默认运行测试。

### P1：历史静态文档仍有上游旧内容

证据：

- `docs/guide/develop.html` 仍包含 Node 16、MySQL、外部数据库脚本下载等旧说明。
- `docs/guide/video.html` 仍包含 `xzs-mysql`、MySQL 安装包、MySQL 导入命令等旧说明。
- `sql/README.md` 仍指向外部数据库下载地址。

注意：

- 部署页已在上一提交修过，本项不扩大为“所有 docs 都已过期”。
- 当前问题集中在历史静态站页面和数据库 README 的遗留上游内容。

建议：

- 明确文档源与静态站生成流程，避免直接手改构建产物后再次被旧源覆盖。
- 对 `docs/guide/develop.html`、`docs/guide/video.html`、`sql/README.md` 做 PostgreSQL、Vue 3 + Vite、当前部署方式的内容收口。
- 在发布前检查清单中加入旧关键词扫描，例如 `xzs-mysql`、`Mysql`、`NodeJs 16`、外部 SQL 下载地址。

### P2：发布制品策略需收口

证据：

- `release/web/**` 当前跟踪了较多静态发布文件。
- `release/java` 仍保留 `xzs-3.9.0.jar`。
- 上一提交已删除 `docker/release` 重复 jar 和内置 compose 二进制；当前 `docker/` 下只见 compose 与 README 等部署材料。

影响：

- 源码、构建产物和部署材料边界不够清晰，容易带来体积增长和重复制品。
- 发布包更新可能产生大量无业务意义的 diff，影响审查效率。

建议：

- 决定 `release/` 是否继续作为“可直接部署的发布快照”纳入版本管理。
- 如果保留，需要建立发布前检查清单和生成脚本，确保 jar、前端静态包、Docker/Fly 入口一致。
- 如果不保留，应改由 CI artifact、Release 附件或部署脚本生成，仓库只跟踪源码和部署模板。

### P2：`ExamPaperServiceImpl` 是业务聚合热点

证据：

- `source/xzs/src/main/java/com/mindskip/xzs/service/impl/ExamPaperServiceImpl.java` 约 567 行。
- 同一类同时包含保存试卷、GESP 组卷、智能训练抽题、VM 转换等职责。

影响：

- 后续改动试卷保存、真题导入或智能训练时，容易在同一个服务类里互相影响。
- 当前规模尚未要求立即大重构，但继续叠加功能会增加回归风险。

建议：

- 不做脱离业务需求的立刻大重构。
- 下一次相关功能改动时顺手拆分：例如把 GESP 组卷、智能训练抽题、试卷 VM 转换逐步抽到独立协作者类或服务中。
- 拆分前先补围绕现有行为的测试或验证脚本，避免只做结构移动却改变业务结果。

## 可帮助用户的功能建议

- `scripts/verify-all.ps1`：提供本地统一验证入口，覆盖后端、前端、发布一致性和文档旧关键词扫描。
- GitHub Actions：把统一验证入口接入 PR 和主分支，形成最低工程健康门槛。
- 题库导入体检页：在管理端展示 GESP/CSP 题库导入数量、缺失年份、重复题和异常题型，降低题库维护成本。
- Fly 线上健康检查脚本：补充部署后检查，包括应用健康、数据库连接、静态资源、关键页面和日志摘要。
- 发布前检查清单：覆盖版本号、jar/静态包一致性、数据库迁移、文档旧内容、Docker/Fly 配置和回滚路径。

## 推荐执行顺序

### 第 1 阶段：CI + `verify-all`

目标：

- 建立统一、本地可运行、CI 可复用的验证入口。

范围：

- 新增 `scripts/verify-all.ps1`。
- 新增 GitHub Actions 工作流。
- 明确哪些构建路径可以显式跳过测试，哪些发布/CI 路径必须运行测试。

验收标准：

- 本地执行 `scripts/verify-all.ps1` 能完成后端测试、前端构建和已有发布一致性检查。
- GitHub Actions 能在 PR 或 push 时运行同一套核心检查。
- CI 日志能清楚区分测试失败、构建失败和静态发布检查失败。

风险/注意事项：

- 后端当前默认 `<skipTests>true</skipTests>`，改动 Maven 默认行为前要确认本地开发体验和 Docker 构建耗时。
- 前端依赖安装可能受网络和锁文件影响，CI 需要固定 Node 版本与缓存策略。

### 第 2 阶段：文档源/静态站收口

目标：

- 消除历史静态文档中的上游旧说明，并明确后续文档更新入口。

范围：

- 修正 `docs/guide/develop.html`、`docs/guide/video.html`、`sql/README.md` 中与当前项目不一致的 MySQL、Node 16、外部 SQL 下载等内容。
- 查清静态站源文件或生成方式，避免只改产物导致后续覆盖。
- 在验证脚本中加入旧关键词扫描。

验收标准：

- 相关页面不再指向 `xzs-mysql`、MySQL 初始化脚本或外部 SQL 下载。
- 文档描述与 PostgreSQL、Vue 3 + Vite、当前部署材料一致。
- 发布前检查能发现典型旧关键词回流。

风险/注意事项：

- 不要把已修过的部署页重新纳入大范围重写。
- 静态 HTML 可读性差，修改前应确认是否存在更上游的 Markdown/VuePress 源。

### 第 3 阶段：发布制品策略

目标：

- 明确源码仓库是否继续跟踪发布制品，并降低重复制品和大 diff。

范围：

- 评估 `release/web/**`、`release/java/xzs-3.9.0.jar` 的保留价值。
- 选择“仓库内发布快照”或“CI 生成 artifact/Release 附件”中的一种主策略。
- 更新发布脚本、忽略规则和发布前检查清单。

验收标准：

- 发布制品来源、生成命令、校验方式和存放位置有明确说明。
- 仓库中不再出现同一 jar 或静态包在多个目录重复保存。
- 发布前检查能确认 jar、前端静态包、Docker/Fly 入口和数据库迁移的一致性。

风险/注意事项：

- 如果移除已跟踪制品，需要确认现有部署流程是否依赖仓库内文件。
- 如果保留制品，需要接受发布 commit 可能包含大量静态文件变化，并用脚本降低人工失误。

### 第 4 阶段：业务热点拆分

目标：

- 在不改变业务行为的前提下，逐步降低 `ExamPaperServiceImpl` 的职责密度。

范围：

- 优先围绕下一次相关功能改动拆分，而不是单独发起大重构。
- 候选拆分方向包括 GESP 组卷、智能训练抽题、试卷 VM 转换。
- 为关键行为补最小测试或验证脚本。

验收标准：

- 相关功能改动后，原有试卷保存、GESP 导入、智能训练抽题和页面转换行为可验证。
- `ExamPaperServiceImpl` 新增职责停止增长，部分独立职责迁出到命名清晰的组件。
- 拆分提交保持小步、可审查、可回退。

风险/注意事项：

- 该类连接数据库、题目、试卷结构和 VM 转换，缺少测试时直接重构风险较高。
- 应避免只追求行数减少而引入跨服务循环依赖或事务边界变化。

### 第 5 阶段：运营辅助功能

目标：

- 让题库维护、线上部署和发布前检查更容易被非核心开发者执行。

范围：

- 管理端题库导入体检页。
- Fly 线上健康检查脚本。
- 发布前检查清单。
- 可选：将检查结果输出为 Markdown 报告，便于归档。

验收标准：

- 题库导入状态能在管理端或脚本报告中快速定位缺失、重复、异常。
- Fly 部署后能一键检查应用健康、数据库连接和关键页面。
- 发布前检查清单能被主线程用于最终审查。

风险/注意事项：

- 运营辅助功能应优先复用已有脚本和接口，不要先引入新的复杂平台。
- 健康检查脚本不能依赖生产敏感凭据写入仓库。

## Harness 执行约束

- 涉及代码或配置变更时，由 subagent 执行具体修改；创建 subagent 前必须写清目标、修改范围和是否提交 Git，且不 fork 上下文。
- 主线程负责读取仓库事实、制定任务边界、审查 subagent 结果、运行验证命令和汇总风险。
- subagent 不 commit、不 push；主线程审查验证后按项目规则统一提交、推送。
- 如果缺少必要上下文、验证失败或发现协作者并行改动影响当前任务，应先停止扩大改动范围，说明冲突点后再决定下一步。
