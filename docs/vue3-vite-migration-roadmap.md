# Vue 3 + Vite 长期迁移方案

## 目标

阶段五定义长期迁移路线，不在当前优化分支直接迁移 Vue 3，也不替换生产构建。目标是把两个 Vue 2.7 + Vue CLI 4 前端迁移到 Vue 3 + Vite，同时保留后端内置 static 部署方式和现有业务行为。

当前约束：

- 管理端和学生端是两个独立前端，不应强行合并。
- 后端仍从 `source/xzs/src/main/resources/static/admin` 和 `source/xzs/src/main/resources/static/student` 提供页面。
- 现有 `publicPath: './'` 必须映射为 Vite `base: './'`。
- Element UI 2.x、Vue Router 3、Vuex 3、`require.context`、Webpack `svg-sprite-loader`、UEditor 都是迁移关注点。
- 管理端有更多复杂资产：UEditor、ECharts、Excel、CodeMirror、Dashboard、后台布局和权限菜单。
- 学生端相对轻量，但登录、考试、答题、交卷、个人中心路径必须独立验收。

## 总体策略

采用先兼容、后替换、分端推进的策略：

1. 先完成 Vue 2.7 + Vite spike，确认构建工具、静态资源和后端部署路径问题。
2. 建立 Vue 3 基础壳工程，先迁移学生端，再迁移管理端。
3. UI 库、路由、状态、富文本分别做独立改造，不把所有风险压在一次大合并中。
4. 每个阶段都保留 Vue 2 生产构建可发布，直到 Vue 3 版本通过完整验收。
5. 最终切换只发生在两个前端各自的发布脚本和后端 static 同步脚本明确支持后。

## 迁移拆分

### 1. 基础工程与构建

目标：

- 新建 Vue 3 + Vite 工程结构，分别对应 `xzs-admin` 和 `xzs-student`。
- 保留当前 `admin`、`student` 输出目录语义，迁移过程中使用 `admin-vue3`、`student-vue3` 避免覆盖生产产物。
- Vite 配置固定 `base: './'`、`assetsDir: 'static'`、`@` alias、`/api` 代理和端口。
- 环境变量改为 `import.meta.env`，保留 `VITE_APP_URL` 或建立兼容映射后逐步替换 `process.env.VUE_APP_URL`。

任务：

- 盘点 `.env.*` 中所有 `VUE_APP_` 变量。
- 将 `public/index.html` 改为 Vite HTML 模板语义。
- 将 Webpack 专属能力替换为 Vite 原生能力或插件。
- 建立独立构建命令和体积报告，不接入生产发布。

验收：

- 两个前端可独立 `vite dev`。
- 两个前端可独立 `vite build`。
- 构建产物在临时静态服务中以 `/admin/`、`/student/` 路径正常访问。

### 2. Vue 入口和全局插件

目标：

- 从 `new Vue({ router, store, render }).$mount('#app')` 迁移到 `createApp(App).use(router).use(store).mount('#app')`。
- 替换 `Vue.use`、`Vue.component`、`Vue.prototype` 等 Vue 2 全局 API。
- 梳理 `$message`、`$loading`、`$$router` 这类全局挂载方式。

任务：

- 建立 `src/plugins/`，集中注册 UI、图标、全局属性。
- 将 `Vue.prototype.$$router` 替换为路由实例导入、`app.config.globalProperties` 或请求层显式依赖。
- 全局过滤器如果存在，改为方法、computed、工具函数或局部注册。
- 检查所有组件中的 `$listeners`、`.sync`、自定义 `v-model`、事件透传行为。

验收：

- 登录流程、路由守卫、标题设置、进度条和接口错误跳转行为一致。
- 控制台无 Vue 3 迁移警告和全局属性缺失错误。

### 3. UI 库：Element UI 到 Element Plus

Element UI 2.x 不支持 Vue 3，长期方案应迁移到 Element Plus。Element Plus 官方提供 Element UI 到 Element Plus 的迁移工具，但本项目不能只依赖自动转换，必须逐页验收交互差异。

任务：

- 统计两个前端实际使用的 `el-*` 组件、表单校验、弹窗、消息、表格、分页、上传、日期选择器。
- 建立 Element Plus 按需引入方案，优先利用 ESM tree shaking 和样式自动导入。
- 管理端保留或重建 `element-variables.scss` 对应的主题变量，确认 SCSS 变量和 CSS 变量迁移边界。
- 逐页处理 breaking changes：表单校验触发、弹窗事件、表格插槽、分页事件、上传组件、日期格式。
- 用小范围页面先验证：登录页、列表页、编辑表单页、Dashboard。

验收：

- 所有表单校验提示、禁用状态、loading 状态、确认弹窗和消息提示行为一致。
- 表格分页、筛选、排序和批量操作行为一致。
- 管理端主题颜色和布局密度不明显回退。

参考：

- [Element Plus migration guide](https://element-plus.org/en-US/guide/migration)
- [Element Plus quick start](https://element-plus.org/en-US/guide/quickstart)

### 4. Router：Vue Router 3 到 4

目标：

- 将 `vue-router` 3 迁移到 `vue-router` 4。
- 保留 hash 模式，降低后端 Spring Boot fallback 改造风险。
- 保持现有路由守卫、动态标题、埋点、权限菜单初始化行为。

任务：

- `new Router(...)` 改为 `createRouter({ history: createWebHashHistory(), routes })`。
- 守卫中的 `next` 风格可先保留，再逐步改为返回值风格。
- 检查动态路由、重定向、404、登录后跳转和权限菜单生成。
- 管理端 `store.commit('router/initRoutes')` 的调用时机需要重新验证，避免每次导航重复初始化。
- 学生端 body 背景色逻辑需要确保路由切换后仍清理。

验收：

- 登录前访问受保护页面会跳登录，登录后回到目标页面。
- 菜单点击、面包屑、刷新、前进后退、404 行为一致。
- 百度统计或其他埋点不因路由 fullPath 变化丢失。

### 5. 状态管理：Vuex 3 到 Pinia 或 Vuex 4

建议优先评估 Pinia，Vue 官方状态管理已经转向 Pinia；若要最小化一次性改动，可用 Vuex 4 作为过渡。但本项目长期迁移不应停留在 Vuex 4。

任务：

- 管理端先盘点 Vuex modules：用户、路由、权限、设置、考试和 dashboard 相关状态。
- 学生端盘点登录态、用户信息、考试过程、答题缓存和页面状态。
- 将 `require.context('./modules')` 改为显式导入或 `import.meta.glob`。
- 先迁移无副作用模块，再迁移依赖接口和路由的模块。
- 请求层不要直接依赖 Vue 实例；错误跳转、loading、message 通过可测试的服务注入。

验收：

- 刷新后用户态、菜单和权限恢复正确。
- 考试答题状态不丢失、不串题、不误提交。
- 接口 401/403、业务错误和网络错误处理一致。

参考：

- [Pinia migration from Vuex](https://pinia.vuejs.org/cookbook/migration-vuex.html)
- [Vuex official note on Pinia](https://vuex.vuejs.org/)

### 6. 富文本：UEditor 迁移或替换

管理端 UEditor 是迁移风险最高的单点之一。它依赖全局脚本、iframe 弹窗、公式插件和后端上传接口。Vue 3 迁移有两条路线：

- 保守路线：保留 UEditor 静态资源，重写 Vue 3 wrapper，继续动态加载 `window.UE`。
- 长期路线：替换为 Vue 3 生态富文本编辑器，并迁移公式、图片上传、HTML 回显和历史题目内容兼容。

建议先走保守路线，原因是题库内容、公式和历史 HTML 兼容比组件现代化更关键。

任务：

- 抽出 UEditor loader，避免组件多次挂载重复插入脚本。
- 用 Vue 3 `onMounted`、`onBeforeUnmount` 管理实例生命周期。
- 保持 `UEDITOR_HOME_URL` 指向 `admin/components/ueditor/`。
- 验证题目编辑、选项编辑、解析编辑、公式插件、图片上传和内容回显。
- 评估替代编辑器时，必须先建立历史内容兼容样本集。

验收：

- 旧题目 HTML 能完整回显。
- 新建题目保存后，学生端展示和答题不受影响。
- 公式编辑和图片上传可用。

### 7. SVG、静态资源和第三方库

任务：

- SVG sprite 从 `svg-sprite-loader` 迁移到 Vite 插件，保持 `#icon-[name]` 兼容。
- `require.context` 全部替换为 `import.meta.glob` 或显式导入。
- 检查 ECharts、CodeMirror、xlsx、file-saver、jszip、screenfull、nprogress 在 Vue 3 + Vite 下的打包和运行。
- `public` 下静态资源继续作为原样复制资源处理，禁止在迁移中改动后端 static 目录结构。

验收：

- 所有菜单图标、按钮图标和外链图标显示正常。
- Dashboard 图表、Excel 导入导出、全屏、进度条行为一致。
- 构建产物没有异常大 chunk；必要时配置 manualChunks。

### 8. 构建部署

任务：

- 保留 `base: './'`，继续产出 `static/` 资源目录。
- 将 Vue 3 构建产物同步到后端 static 的脚本必须单独开关，不能影响 Vue 2 生产构建。
- 后端无需为 history 模式新增 fallback，除非明确决定从 hash 路由迁移到 history 路由。
- 建立构建体积和耗时基线，和 Vue CLI 结果对比。

验收：

- 后端 jar 内 `/admin/index.html`、`/student/index.html` 正常加载相对资源。
- 后端启动后两个前端可登录、刷新、跳转。
- 构建时间、产物体积和首屏请求数不劣于 Vue 2 基线，或有明确可接受原因。

### 9. 测试与验收

最低测试矩阵：

- 静态检查：lint、构建、类型检查或等价脚本。
- 单端冒烟：登录、退出、菜单、列表、详情、编辑、删除确认、错误提示。
- 管理端专项：题目管理、试卷管理、用户管理、Dashboard、UEditor、Excel、图表。
- 学生端专项：首页、登录、试卷列表、开始考试、答题、交卷、结果查看、个人中心。
- 部署专项：后端内置 static、相对路径、刷新、浏览器缓存、接口代理。
- 回归数据：至少准备一组含文本题、图片题、公式题、选择题、判断题、简答题的题库样本。

建议引入 Playwright 做端到端冒烟，但不把端到端测试作为迁移第一步的阻塞项。先保证手工验收清单稳定，再自动化高频路径。

## 推荐里程碑

### M0：盘点与冻结

- 冻结 Vue 2 生产构建入口。
- 记录两个前端依赖、路由、状态模块、Element 组件、UEditor 使用点。
- 完成 Vue 2.7 + Vite spike 结果归档。

### M1：学生端 Vue 3 原型

- 建立学生端 Vue 3 + Vite 壳。
- 完成 Router 4、Element Plus、状态管理基础迁移。
- 跑通登录、试卷列表、考试、交卷主链路。

### M2：管理端基础迁移

- 建立管理端 Vue 3 + Vite 壳。
- 完成布局、登录、菜单、权限、列表和基础表单。
- 完成 SVG、ECharts、Excel、CodeMirror 基础适配。

### M3：管理端 UEditor 和题库闭环

- 完成 UEditor Vue 3 wrapper。
- 跑通题目新增、编辑、公式、图片、保存、学生端展示。
- 建立题库样本回归清单。

### M4：生产候选

- Vue 3 构建产物接入独立发布脚本。
- 后端 static 同步增加显式 Vue 3 开关。
- 完整冒烟、体积和耗时对比通过。

### M5：切换与清理

- 切换默认生产构建到 Vue 3。
- 保留 Vue 2 回退分支和最后一次可发布产物。
- 删除过期 Vue CLI 配置、Webpack loader 和 Vue 2-only 依赖。

## 不建议做的事

- 不建议在同一提交里同时替换 Vue、Vite、Element、Router、状态管理和 UEditor。
- 不建议把两个前端合并成一个 Vite monorepo 作为迁移第一步。
- 不建议为了适配 Vue 3 改后端接口或数据库。
- 不建议直接把 UEditor 替换为新编辑器，除非先证明历史题目 HTML 和公式完全兼容。
- 不建议在 Vue 2.7 + Vite spike 未完成前启动大规模 Vue 3 改造。

## 最终切换条件

- 两个前端 Vue 3 版本通过完整手工验收。
- 管理端 UEditor 和题库样本通过回归。
- 后端内置 static 部署通过。
- 构建耗时、产物体积和首屏加载数据达到预设目标。
- Vue 2 生产构建有明确回退标签或分支。
- 发布脚本和文档明确 Vue 3 是默认构建，Vue CLI 不再被隐式调用。

## 当前执行结果

截至阶段 9，学生端和管理端 Web 已完成 Vue 3 + Vite 覆盖式迁移。默认生产构建、后端 `/student` 和 `/admin` static 入口、Markdown/KaTeX/代码高亮渲染、管理端 UEditor 题库闭环和主要管理端业务模块均已切换到 `frontend/` 工作区。

旧 Vue 2 Web 工程、Vue CLI 生产入口和 Vue 2.7 + Vite 过渡 spike 已删除。后续工作不再是迁移阻塞，重点转为构建 chunk 拆分、大试卷渲染缓存、分批渲染和发布文档站更新。
