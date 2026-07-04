# 前端最终架构分阶段迁移路线

## 目标

本路线面向最终架构迁移，不再以 Vue 2 过渡为目标。迁移目标是把现有管理端和学生端从 Vue 2.7 + Vue CLI 4 迁移到 Vue 3 + Vite 的现代前端架构，并重点解决以下问题：

- 本地开发时修改代码后页面能快速热更新。
- 试卷页按需加载题目渲染能力，降低首次进入答题页的 JS 下载和解析成本。
- Markdown、KaTeX 公式、代码高亮成为独立可优化模块，而不是散落在业务组件中。
- 保留 Spring Boot 后端 API 和现有数据库模型，避免前后端同时重写。
- 保留后端内置 static 部署能力，同时为后续 Nginx/CDN 独立静态部署预留空间。
- 迁移完成后直接覆盖旧学生端、旧管理端和现有 `/student`、`/admin` 发布入口，不做新旧系统并行。

## 架构选型结论

推荐最终架构：

- Vue 3
- Vite 最新稳定版
- TypeScript
- Vue Router 4
- Pinia
- Element Plus
- pnpm workspace
- DOMPurify
- KaTeX
- markdown-it 或可替换的 Markdown 渲染适配层
- Shiki 或 highlight.js 按需语言加载
- TipTap 或同等级 ProseMirror 系富文本编辑器，替换 UEditor

不建议把 Nuxt、Next.js 或 SvelteKit 作为第一目标：

- 本项目是登录后的考试系统和后台管理系统，SEO 和 SSR 收益有限。
- Next.js 需要从 Vue 迁移到 React，成本和风险明显高于收益。
- SvelteKit 性能潜力好，但等同重写，团队和生态迁移成本过高。
- Nuxt 适合 Vue SSR/混合渲染应用，但当前系统更适合作为前后端分离 SPA，由 Spring Boot 继续提供 API。

参考资料：

- Vue 官方工具链建议：`https://vuejs.org/guide/scaling-up/tooling`
- Vue CLI 维护模式说明：`https://cli.vuejs.org/guide/creating-a-project.html`
- Vite 架构与 HMR 说明：`https://vite.dev/guide/why`
- Nuxt 渲染模式说明：`https://nuxt.com/docs/4.x/guide/concepts/rendering`
- Vue 2 EOL 说明：`https://v2.vuejs.org/eol/`

## 目标目录模板

建议先新增现代前端工作区承载重构，阶段验收后直接覆盖旧工程和旧发布入口。这里的 `frontend/` 是重构工作区，不是长期并行系统。

```text
frontend/
  package.json
  pnpm-workspace.yaml
  tsconfig.base.json
  apps/
    student/
      index.html
      vite.config.ts
      src/
    admin/
      index.html
      vite.config.ts
      src/
  packages/
    api-client/
    question-renderer/
    ui/
    shared/
    config/
```

职责划分：

- `apps/student`：学生端应用，优先迁移，用于验证登录、试卷列表、答题、交卷和题目渲染。
- `apps/admin`：管理端应用，后迁移，重点验证题库编辑、试卷管理、用户管理和富文本能力。
- `packages/api-client`：接口请求、登录态、错误处理、API 类型定义。
- `packages/question-renderer`：题干、选项、解析的 Markdown/HTML/公式/代码高亮渲染。
- `packages/ui`：跨端通用 UI 组件，如分页、空状态、题目块、布局基础组件。
- `packages/shared`：枚举、格式化函数、权限常量、通用工具。
- `packages/config`：ESLint、Prettier、TypeScript、Vite 公共配置。

## 核心设计原则

### 1. 覆盖式重构

不建立 `/student-v3`、`/admin-v3` 这类长期并行入口，也不维护两套生产前端。每个端完成验收后，直接覆盖对应旧端源码、构建脚本和后端 static 发布入口。

允许在迁移阶段使用 `frontend/` 作为重构工作区；它的目标是最终替换 `source/vue/xzs-student` 和 `source/vue/xzs-admin`，不是成为第三套前端。

### 2. 学生端优先

学生端链路更短，而且当前性能痛点集中在试卷加载和题目渲染。先迁学生端能最快验证最终架构是否有效。

### 3. 题目渲染独立

`question-renderer` 必须独立成包，避免业务组件直接依赖 MarkdownIt、KaTeX、highlight.js。这样可以单独做缓存、懒加载、代码分割和测试。

### 4. 管理端富文本替换实现

管理端不保留 UEditor wrapper 路线。功能必须保留，但实现可以替换。推荐用 TipTap 或同等级 ProseMirror 系编辑器重建题库编辑能力，并提供历史 HTML 内容导入、公式节点、图片上传、代码块、预览和保存能力。

### 5. API 不重写

迁移不改变 Spring Boot API、数据库结构、认证模型和题库数据结构。前端通过 `api-client` 适配现有接口。

## 阶段 0：基线冻结与验收样本

### 目标

冻结当前 Vue 2 行为基线，准备新架构迁移的对照数据和回归样本。

### 任务

- 记录当前学生端和管理端的关键页面清单。
- 记录当前构建耗时、主要 JS/CSS 体积、答题页加载耗时。
- 准备题库样本：
  - 普通文本题
  - HTML 包裹题干
  - `$N$` 行内公式
  - `$$...$$` 块级公式
  - C++/Java/Python 代码块
  - 图片题
  - 单选、多选、判断、填空、简答
- 保存当前可发布分支或 tag。

### 产出

- `.tmp/benchmarks/frontend-baseline-YYYYMMDD.md`
- `docs/frontend-modernization-test-cases.md`
- 覆盖前安全 Git tag，例如 `vue2-baseline-YYYYMMDD`

### 验收

- 当前系统能完整启动、登录、答题和管理题目，作为覆盖前行为基线。
- 基线数据可重复测量。

## 阶段 1：现代前端工作区骨架

### 目标

建立 `frontend/` monorepo 和学生端 Vue 3 + Vite 基础壳，不迁移复杂业务。

### 任务

- 新增 `frontend/package.json` 和 `pnpm-workspace.yaml`。
- 新建 `apps/student`，使用 Vue 3 + Vite + TypeScript。
- 配置 `base: './'`、`assetsDir: 'static'`、`@` alias、开发代理 `/api -> http://localhost:8000`。
- 接入 Vue Router 4、Pinia、Element Plus。
- 建立统一 layout、登录页壳、404 页。
- 配置 ESLint、Prettier、TypeScript 检查。

### 产出

- `frontend/apps/student`
- `frontend/packages/config`
- `frontend/packages/shared`
- `frontend/scripts/dev-student.ps1`
- `frontend/scripts/build-student.ps1`

### 验收

- `pnpm --filter student dev` 可启动。
- 修改 `.vue` 文件后浏览器能 HMR 更新。
- `pnpm --filter student build` 通过。
- 构建产物可用静态服务访问。

## 阶段 2：API Client 与登录链路

### 目标

跑通学生端登录、退出、当前用户、接口错误处理和路由鉴权。

### 任务

- 新建 `packages/api-client`。
- 封装 axios 或 fetch 实例。
- 统一处理：
  - `401/502` 跳登录
  - `500/501` 错误提示
  - session cookie
  - 请求超时
- 迁移学生端登录页和注册入口。
- 建立 Pinia 用户 store。
- 保持现有 `/api/user/login` 行为。

### 产出

- `packages/api-client`
- `apps/student/src/stores/user.ts`
- 登录、退出、鉴权路由

### 验收

- `student / 123456` 可登录。
- 登录后刷新页面仍能恢复用户态。
- 未登录访问受保护页面会跳转登录。
- 接口错误提示行为清晰。

## 阶段 3：Question Renderer 独立包

### 目标

把题目渲染从业务页面中剥离，解决 Markdown/公式/代码高亮带来的性能和维护问题。

### 任务

- 新建 `packages/question-renderer`。
- 支持输入：
  - 纯文本 Markdown
  - 历史 HTML 片段
  - HTML 内文本节点 `$...$` 公式
  - 代码块和行内代码
- 使用 DOMPurify 做安全清理。
- KaTeX 按需加载。
- 代码高亮按语言懒加载。
- 禁止无语言代码块默认 `highlightAuto`，避免大试卷 CPU 抖动。
- 对相同内容做渲染缓存。
- 暴露 Vue 组件：
  - `QuestionMarkdown`
  - `QuestionStem`
  - `QuestionOption`
  - `QuestionAnalysis`

### 产出

- `packages/question-renderer`
- 单元测试覆盖 HTML 包裹公式、代码块跳过、XSS 清理、缓存命中。

### 验收

- `$N$`、`$35$`、`$$x^2$$` 正确渲染。
- `<pre><code>$N$</code></pre>` 不渲染为公式。
- HTML 属性中的 `$N$` 不被错误处理。
- 25 题试卷渲染耗时有可测量改善。
- 题目渲染包可独立测试，不依赖完整学生端。

## 阶段 4：学生端核心业务迁移

### 目标

迁移学生端核心路径，达到可直接覆盖旧学生端的标准。

### 任务

- 迁移首页。
- 迁移试卷列表。
- 迁移智能训练入口。
- 迁移答题页。
- 迁移交卷和考试结果弹窗。
- 迁移考试记录。
- 迁移错题本。
- 迁移个人中心和消息页。
- 答题页引入 `question-renderer`。
- 对大试卷评估分批渲染或虚拟滚动。

### 产出

- `apps/student` 完整学生端主链路。
- 学生端 E2E 冒烟脚本。
- 学生端性能对比报告。

### 验收

- 登录、试卷列表、开始答题、选择答案、交卷、查看记录可完整跑通。
- 含公式和代码的题目显示正确。
- 首次进入答题页的 JS 体积低于迁移前基线，或有明确、已实现的拆包策略。
- HMR 可用于日常页面开发。

## 阶段 5：学生端覆盖切换

### 目标

把 Vue 3 学生端直接覆盖旧学生端源码和现有 `/student` 发布入口。

### 任务

- 用 `frontend/apps/student` 覆盖 `source/vue/xzs-student`，或把旧目录替换为新 Vue 3 工程。
- 更新学生端构建脚本，默认构建 Vue 3 版本。
- 构建产物直接同步到 `source/xzs/src/main/resources/static/student`。
- 验证 Spring Boot 内置 static 下的相对路径。
- 验证 gzip 或 brotli 配置。
- 验证浏览器强刷和普通刷新。
- 删除旧学生端 Vue CLI 依赖、Webpack 配置和过期脚本入口。

### 产出

- Vue 3 版 `source/vue/xzs-student`
- 覆盖后的 `source/xzs/src/main/resources/static/student`
- 学生端默认构建脚本

### 验收

- `/student/index.html` 直接访问 Vue 3 学生端。
- `/api` 请求正常。
- 静态资源有压缩响应。
- 项目中不存在学生端新旧生产入口切换开关。

## 阶段 6：管理端骨架迁移

### 目标

建立管理端 Vue 3 + Vite 应用骨架，迁移登录、布局、菜单、权限和基础列表能力。

### 任务

- 新建 `apps/admin`。
- 复用 `api-client`、`shared`、`ui`。
- 迁移登录、退出、菜单、路由守卫。
- 迁移 Dashboard 基础布局。
- 迁移用户管理、学科管理等低风险列表页。
- 接入 Element Plus 表格、分页、表单、弹窗。

### 产出

- `frontend/apps/admin`
- 管理端基础路由和权限模型

### 验收

- 管理端可登录。
- 菜单和权限显示正确。
- 基础列表查询、分页、编辑弹窗可用。
- HMR 可用于管理端开发。

## 阶段 7：管理端题库与富文本迁移

### 目标

迁移管理端题库编辑闭环，用新富文本实现替换 UEditor，同时保留现有题库编辑功能和历史内容兼容。

### 任务

- 选型并接入 TipTap 或同等级 ProseMirror 系编辑器。
- 实现历史 HTML 内容导入，将旧题库 HTML 转换为新编辑器文档模型。
- 实现保存序列化，保证后端仍可存储并被学生端 `question-renderer` 正确展示。
- 实现公式节点，支持行内公式和块级公式。
- 实现图片上传节点，复用现有上传接口。
- 实现代码块节点，支持语言标记和预览高亮。
- 迁移题目新增、编辑、选项编辑、解析编辑。
- 实现题目预览，预览结果必须复用 `question-renderer`。
- 保存后用新学生端展示验证。
- 删除 UEditor 静态资源和加载代码。

### 产出

- 新富文本编辑器组件，例如 `apps/admin/src/components/RichTextEditor`
- 历史 HTML 导入/导出适配层
- 题库管理核心页面
- 题库编辑回归样本

### 验收

- 历史题目 HTML 可完整导入、编辑和保存。
- 新建题目保存后学生端展示正确。
- 公式、图片、代码块不丢失。
- 多个编辑器实例创建和销毁稳定。
- 项目中不再依赖 UEditor 运行时。

## 阶段 8：管理端剩余模块迁移

### 目标

完成管理端剩余业务模块，并处理第三方库兼容。

### 任务

- 迁移试卷管理。
- 迁移考试记录和阅卷。
- 迁移用户、消息、任务、日志等模块。
- 迁移 ECharts、xlsx、file-saver、jszip、CodeMirror、screenfull、nprogress。
- 迁移 SVG icon 方案到 Vite 插件或组件化图标。
- 建立管理端 E2E 冒烟脚本。

### 产出

- 完整 `apps/admin`
- 管理端第三方库兼容报告

### 验收

- 管理端主要模块达到覆盖旧管理端的标准。
- Excel 导入导出、图表、代码编辑器、全屏功能可用。
- 构建产物体积和 chunk 拆分可解释。

## 阶段 9：管理端覆盖切换与统一发布

### 目标

把 Vue 3 管理端直接覆盖旧管理端源码和现有 `/admin` 发布入口，并形成统一发布脚本。

### 任务

- 用 `frontend/apps/admin` 覆盖 `source/vue/xzs-admin`，或把旧目录替换为新 Vue 3 工程。
- 更新管理端构建脚本，默认构建 Vue 3 版本。
- 新增或改造 `scripts/build-frontend.ps1`。
- 新增或改造 `scripts/sync-web-static.ps1`。
- 新增或改造 `scripts/build-all.ps1`。
- 后端 compression 补齐 JS/CSS/JSON/HTML mime types。
- 明确生产输出目录：
  - `static/student`
  - `static/admin`
- 覆盖前创建安全 Git tag，只作为代码历史保护，不作为线上并行版本。
- 更新部署文档。
- 删除旧管理端 Vue CLI 依赖、Webpack 配置、UEditor 静态资源和过期脚本入口。

### 产出

- 默认构建脚本直接构建 Vue 3 学生端和管理端
- 部署说明

### 验收

- 后端 jar 内 `/student/index.html`、`/admin/index.html` 均为 Vue 3 版本。
- 两端完整冒烟通过。
- 静态资源压缩和缓存头正确。
- 项目中不存在 Vue 2 生产构建入口。

## 阶段 10：旧工程清理与结构收敛

### 目标

删除 Vue 2 技术债和过期构建链路，使仓库只保留 Vue 3 前端实现。

### 任务

- 确认 `source/vue/xzs-admin` 和 `source/vue/xzs-student` 已是 Vue 3 工程。
- 删除迁移期 `frontend/apps/*` 中已覆盖到旧目录的重复应用，或将 `source/vue/*` 改为指向最终 monorepo 结构。
- 删除 Vue CLI、Webpack loader、Vue 2-only 依赖。
- 清理旧构建脚本。
- 更新 `PROJECT_STRUCTURE.md`、`AGENTS.md` 和 `docs/project-structure/`。
- 更新开发启动说明。

### 产出

- 简化后的项目结构文档
- 清理提交

### 验收

- 新开发者只需按 Vue 3 文档启动项目。
- 仓库中没有 Vue 2 生产构建入口。
- 文档和脚本没有过期入口。

## 性能优化专项

这些优化应贯穿阶段 3 到阶段 9：

### 静态资源压缩

Spring Boot 当前可能没有对 `application/javascript` 启用压缩。需要明确配置：

```yaml
server:
  compression:
    enabled: true
    min-response-size: 2KB
    mime-types:
      - text/html
      - text/css
      - application/javascript
      - application/json
      - image/svg+xml
```

### 试卷页拆包

答题页建议形成独立 chunk：

- `exam-page`
- `question-renderer`
- `katex`
- `code-highlight-core`
- `code-highlight-lang-cpp`
- `code-highlight-lang-java`
- `code-highlight-lang-python`

### 渲染缓存

以内容 hash 为 key 缓存 Markdown/HTML 渲染结果：

- 同一题干重复展示不重复渲染。
- 答题页状态变化不触发题干重新渲染。
- 解析页和错题页可复用渲染缓存。

### 分批渲染

大试卷页面避免一次性同步渲染所有题目：

- 首屏先渲染前几题。
- 空闲时间继续渲染后续题目。
- 或使用虚拟滚动，但要确保题号锚点和答题状态可靠。

## 测试策略

### 单元测试

- `question-renderer`：Markdown、HTML、公式、代码块、XSS、缓存。
- `api-client`：错误码、登录态、超时、跳转。
- `shared`：枚举和格式化。

### 组件测试

- 题目组件。
- 选项组件。
- 答题卡组件。
- 表单组件。

### E2E 冒烟

学生端：

- 登录
- 进入试卷列表
- 开始答题
- 选择答案
- 交卷
- 查看考试记录

管理端：

- 登录
- 新建题目
- 编辑公式
- 上传图片
- 保存题目
- 新建试卷
- 学生端答题验证展示

## 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 新富文本编辑器与历史 HTML 兼容不足 | 管理端题库编辑阻塞 | 先建立历史内容样本库和导入/导出适配层，题库闭环不过不进入覆盖切换 |
| Element UI 到 Element Plus 行为差异 | 表单、表格、弹窗回归风险 | 逐页迁移，建立组件使用清单 |
| 历史 HTML 内容不规范 | 题目展示异常 | `question-renderer` 用样本库驱动测试 |
| 覆盖式切换风险集中 | 发布失败影响范围大 | 每个端覆盖前必须完成冒烟、性能和静态资源部署验收，覆盖后立即删除并行入口 |
| 生产部署路径变化 | 静态资源 404 | 坚持 `base: './'`，每阶段做后端 static 冒烟 |
| 一次性迁移范围过大 | 返工风险高 | 学生端先覆盖，管理端后覆盖，题库编辑单独阶段 |

## 推荐执行顺序

优先级最高的最小闭环：

1. 阶段 0：冻结基线。
2. 阶段 1：建 Vue 3 + Vite 学生端骨架。
3. 阶段 2：跑通登录。
4. 阶段 3：完成 `question-renderer`。
5. 阶段 4：跑通学生端答题主链路。

只有这个闭环通过后，才推进管理端迁移。原因是当前最明确的痛点是试卷加载和热更新，学生端能最快验证新架构的真实收益。
