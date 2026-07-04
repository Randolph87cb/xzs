# 打包与运行性能五阶段优化方案

## 目标

降低本项目本地与发布环境的完整打包时间、减少后端 jar 静态资源体积、提升前端首屏资源加载效率，并为后续框架迁移提供可验证路径。

## 当前基线

- 迁移前管理端 Vue CLI `npm run build:prod`：约 98 秒。
- 迁移前学生端 Vue CLI `npm run build:prod`：约 88 秒。
- 后端无变更热打包 `mvn -DskipTests package`：约 11.5 秒。
- 应用启动到端口可用 `start.ps1 -NoDatabase`：约 14.7 秒。
- 后端 `resources/static`：约 8.7 MB。
- 管理端 public 组件资源：约 2.7 MB。

## 本轮实测结果

执行日期：2026-07-03。

有效增量构建口径：跳过 `npm ci/install`，只计生产构建、静态同步和后端打包。

| 阶段 | 命令 | 耗时 |
| --- | --- | ---: |
| 管理端构建 | `.\scripts\measure-build.ps1 -Phase admin -SkipInstall` | 88.99 秒 |
| 学生端构建 | `.\scripts\measure-build.ps1 -Phase student -SkipInstall` | 70.81 秒 |
| 静态资源同步 | `.\scripts\measure-build.ps1 -Phase sync` | 13.98 秒 |
| 后端打包 | `.\scripts\measure-build.ps1 -Phase backend` | 43.54 秒 |
| 合计 | admin + student + sync + backend | 217.32 秒 |

运行启动口径：`.\scripts\measure-build.ps1 -Phase start-nodb` 会执行 `start.ps1 -NoDatabase` 并在结束后调用 `stop.ps1`。

| 次数 | 耗时 | 备注 |
| --- | ---: | --- |
| 第一次 | 38.26 秒 | 冷启动，已自动停止服务 |
| 第二次 | 22.95 秒 | 热启动，已自动停止服务 |

体积收益：

- 管理端 `chunk-vendors`：约 1031.90 KiB / gzip 291.47 KiB 降至 724.74 KiB / gzip 199.40 KiB。
- 学生端 `chunk-vendors`：约 1022.91 KiB / gzip 288.34 KiB 降至 723.90 KiB / gzip 196.25 KiB。
- 后端内嵌静态资源已通过 `scripts/sync-web-static.ps1` 同步为当前构建产物。

仍需关注：

- 管理端和学生端已经完成 Vue 3 + Vite 覆盖迁移，默认生产构建不再调用 Vue CLI。
- 管理端构建仍需要关注 UEditor 静态资源复制、Element Plus 自动导入和大 chunk 拆分。
- 冷安装阶段仍有大量过期依赖和 npm audit 警告，应与构建时间分开统计。

## Harness 结构

### 适用范围

适用于构建、发布、静态资源、前端依赖、框架迁移验证相关优化。不适用于业务功能改造、数据库结构调整、权限逻辑调整。

### 输入

- 当前仓库源码。
- 现有前端构建配置：`frontend/apps/admin`、`frontend/apps/student`。
- 现有后端 Maven 工程：`source/xzs`。
- 上一轮实测基线与构建日志。

### 执行流程

1. 拆分构建/发布脚本，形成可单独计时的 admin、student、backend、sync、all 阶段。
2. 修复 Maven Wrapper，保证后端打包不依赖临时 Maven 路径。
3. 优化 Element UI 引入方式，减少前端 vendor 体积。
4. 建立 Vue 2.7 + Vite 试验路径，用独立文档和脚本验证构建收益。
5. 建立 Vue 3 + Vite 长期迁移方案，明确范围、风险和分阶段验收。

### 角色分工

- 主线程：写方案文件、分配 subagent、整合改动、运行验证、处理 Git。
- subagent：按明确文件范围完成局部修改，不提交 Git、不 push。
- 脚本：输出稳定、可重复的构建与计时结果。

### 检查点

- 每个脚本可单独运行，并返回非零退出码表示失败。
- 前端生产构建通过。
- 后端 `mvn -DskipTests package` 通过。
- 后端 static 与前端构建产物可同步。
- 迁移方案已完成覆盖切换，当前生产构建链路只使用 Vue 3 + Vite。

### 失败处理

- 构建失败时保留日志到 `.tmp/benchmarks` 或 `.tmp/build`。
- subagent 修改冲突时由主线程人工整合。
- Vite/Vue3 迁移验证不通过时只保留方案和风险记录，不替换当前生产构建。

### Git 策略

subagent 不提交、不 push。主线程完成验证后，按项目规则统一 `git add`、中文提交、push；如果远端不可用，则明确报告。

## 阶段一：拆分构建与发布脚本

### 改动

- 新增 `scripts/build-admin.ps1`：只构建管理端。
- 新增 `scripts/build-student.ps1`：只构建学生端。
- 新增 `scripts/package-backend.ps1`：只打后端 jar。
- 新增 `scripts/sync-web-static.ps1`：将前端构建产物同步到后端 `resources/static`。
- 新增 `scripts/build-all.ps1`：串行执行完整一体化发布构建。
- 新增 `scripts/measure-build.ps1`：计时并输出构建阶段耗时。

### 预期收益

后端-only 改动不再强制跑两个前端构建；前端-only 改动也能定位具体耗时来源。

## 阶段二：修复 Maven Wrapper

### 改动

- 补齐 `.mvn/wrapper/maven-wrapper.jar` 或重新生成标准 Maven Wrapper。
- 确认 `mvnw.cmd -DskipTests package` 可在 Windows 下运行。

### 预期收益

后端打包不依赖本机临时 Maven 目录，CI 与本地命令一致。

## 阶段三：Element UI 按需引入

### 改动

- 统计两个 Vue 工程实际使用的 `el-*` 组件与 `$message/$confirm` 等服务。
- 建立 `src/plugins/element-ui.js`，集中注册实际使用组件。
- 移除 `Vue.use(Element)` 全量注册。
- 保持现有主题定制与样式行为。

### 预期收益

降低 `chunk-vendors` 体积，减少首屏 JS/CSS 解析成本。

## 阶段四：Vue 2.7 + Vite 试验路径（已废弃）

### 改动

- 该阶段曾用于低风险验证 Vue 2.7 + Vite 可行性。
- 项目已选择直接推进 Vue 3 + Vite 覆盖式重构，Vue 2.7 spike 文档和测量脚本已删除。
- 后续性能测量以 `scripts/build-admin.ps1`、`scripts/build-student.ps1`、`scripts/build-all.ps1` 和真实后端 static 验证为准。

### 预期收益

以低风险方式确认 Vite 对当前项目的实际构建收益。

### 联网结论

- Vue CLI 官方文档标注其处于 Maintenance Mode，并建议新项目使用基于 Vite 的 create-vue：https://cli.vuejs.org/
- Vite 官方定位是更快、更轻的现代前端工具，开发服务器基于原生 ESM，生产构建使用预配置优化打包：https://vite.dev/guide/
- Vue 2 官方 LTS 页面说明 Vue 2 在 2023-12-31 后不再获得 OSS 更新，包括安全和浏览器兼容修复：https://v2.vuejs.org/lts/

结论：Vue CLI 维护状态和 Vue 2 OSS 终止更新仍是架构升级依据；当前项目已完成 Vue 3 + Vite 覆盖切换，不再维护 Vue 2.7 + Vite 过渡路径。

## 阶段五：Vue 3 + Vite 长期迁移方案

### 改动

- 新增长期迁移设计文档，拆分路由、状态管理、UI 组件库、表单、富文本、构建部署。
- 后续实际执行采用覆盖式路线，学生端和管理端均已切换到 Vue 3 + Vite。

### 预期收益

为后续大版本升级提供可评审路线，避免一次性重写。

### 联网结论

- Element Plus 是 Vue 3 组件库，并提供 Element UI 2.x 到 Element Plus 的迁移指南和迁移工具说明：https://element-plus.org/en-US/guide/migration
- 长期推荐路线是 Vue 3 + Vite + Element Plus；这是架构升级，不应与当前打包瘦身混在同一个变更里。

## 验收命令

```powershell
.\scripts\measure-build.ps1
.\scripts\build-all.ps1
.\source\xzs\mvnw.cmd -DskipTests package
```
