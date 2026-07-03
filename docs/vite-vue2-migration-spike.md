# Vue 2.7 + Vite 试验路径

## 定位

阶段四只建立试验路径，不替换当前生产构建。现有生产链路继续保持：

- 管理端：`source/vue/xzs-admin`，Vue 2.7.16、Vue CLI 4.5、Element UI 2.15、`outputDir: 'admin'`、开发端口 8002。
- 学生端：`source/vue/xzs-student`，Vue 2.7.16、Vue CLI 4.5、Element UI 2.15、`outputDir: 'student'`、开发端口 8001。
- 两端均使用 `publicPath: './'`、`assetsDir: 'static'`、`@` 指向 `src`、`/api` 代理到 `http://localhost:8000`。
- 后端 Spring Boot 内置静态资源位于 `source/xzs/src/main/resources/static/admin` 和 `source/xzs/src/main/resources/static/student`。

Vite 试验的成功标准是可独立证明开发启动、热更新和构建耗时收益，同时保留 Vue CLI 作为可随时回退的唯一生产构建入口。

## 试验边界

- 不修改生产 `package.json`、`package-lock.json`、`src`、后端或 `static`。
- 不把 Vite 构建产物同步进后端 `resources/static`。
- 不新增生产发布脚本对 Vite 的依赖。
- 试验配置应放在独立分支、临时 worktree、或后续专门 spike 目录中；当前文档只描述可执行方案。
- Vite 试验如果需要临时代码改造，应以最小补丁记录，并在试验结束后删除或转入 Vue 3 迁移任务。

## 依赖建议

Vue 2.7 的 Vite 插件应使用 `@vitejs/plugin-vue2`。Vue 官方 Vue 2.7 迁移说明和 Vite 官方插件说明均明确它面向 Vue 2.7 SFC；同时 Vue 2 已 EOL，插件不应视为长期生产依赖。

试验依赖建议只安装在临时分支或临时副本：

```powershell
cd source\vue\xzs-admin
npm install --save-dev vite @vitejs/plugin-vue2 sass

cd ..\xzs-student
npm install --save-dev vite @vitejs/plugin-vue2 sass
```

如试验 SVG sprite 兼容方案，可额外评估 `vite-plugin-svg-icons`。不要在未验证前替换当前 `svg-sprite-loader` 生产配置。

参考：

- [Vue 2.7 migration guide: Vite](https://vuejs.org/v2/guide/migration-vue-2-7.html)
- [Vite official plugins](https://v4.vite.dev/plugins/)
- [@vitejs/plugin-vue2 repository](https://github.com/vitejs/vite-plugin-vue2)

## Vite 配置点

两个前端应分别建独立 Vite 配置，避免把管理端和学生端混成多页面应用。试验输出目录使用 `admin-vite`、`student-vite`，防止覆盖现有 Vue CLI 的 `admin`、`student`。

关键配置：

```js
import path from 'path'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue2'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), ['VUE_APP_', 'BASE_URL'])

  return {
    base: './',
    plugins: [vue()],
    resolve: {
      alias: {
        '@': path.resolve(__dirname, 'src')
      }
    },
    define: {
      'process.env': {
        BASE_URL: JSON.stringify('./'),
        VUE_APP_URL: JSON.stringify(env.VUE_APP_URL || '')
      }
    },
    server: {
      host: 'localhost',
      port: 8002,
      proxy: {
        '/api': {
          target: 'http://localhost:8000',
          changeOrigin: true
        }
      }
    },
    build: {
      outDir: 'admin-vite',
      assetsDir: 'static',
      sourcemap: false,
      emptyOutDir: true
    }
  }
})
```

学生端同样配置，端口改为 8001，输出目录改为 `student-vite`。

需要重点验证：

- `process.env.VUE_APP_URL`：当前请求封装读取 Vue CLI 环境变量，Vite 默认是 `import.meta.env`，试验期先用 `define` 兼容。
- `process.env.BASE_URL`：管理端 UEditor 根据 `BASE_URL` 拼接 `admin/components/ueditor/`，必须验证本地 dev 和 `base: './'` 构建后的路径。
- `public/index.html`：Vite 的 HTML 模板变量和 Vue CLI 不同，若模板中存在 Vue CLI 插值，需要单独处理。
- 浏览器兼容目标：Vue CLI 4 通过 Babel 走旧 browserslist 逻辑；Vite 默认偏现代浏览器。若仍需兼容旧浏览器，需要另设兼容策略并纳入验收。

## 需要适配的项目特性

### Element UI

当前两个前端仍使用 Element UI 2.x。Vue 2.7 + Vite 试验期可以继续保留 Element UI，不在阶段四更换 UI 库。重点验证：

- 管理端 `styles/element-variables.scss` 的 Sass 编译是否正常。
- 学生端 `element-ui/lib/theme-chalk/index.css` 是否被正确打包。
- `$message`、`$confirm`、`$loading` 等挂在 `Vue.prototype` 上的服务是否行为一致。

### UEditor

UEditor 只在管理端存在，资源位于 `source/vue/xzs-admin/public/admin/components/ueditor`，运行时通过动态 `<script>` 顺序加载，并依赖全局 `window.UE`、`window.UEDITOR_HOME_URL`。

试验必须覆盖：

- dev server 下 `admin/components/ueditor/ueditor.config.js?v=3` 可访问。
- 构建产物以 `base: './'` 部署到后端 `/admin/` 后，UEditor 资源路径仍指向 `admin/components/ueditor/`。
- 题目编辑、公式插件、图片弹窗、预览弹窗可用。
- 多个编辑器实例创建和销毁无重复脚本加载问题。

### SVG sprite

当前通过 Webpack `svg-sprite-loader` 处理 `src/icons/svg/*.svg`，组件使用 `<use xlink:href="#icon-name">`。

Vite 不支持 Webpack 的 `require.context` 和 loader 链路，需要二选一：

- 试验保守方案：使用 `vite-plugin-svg-icons`，保持 `#icon-[name]` symbol id，尽量不改 `SvgIcon` 组件。
- 试验显式方案：把 `src/icons/index.js` 的 `require.context` 改成 `import.meta.glob`，并配合 SVG sprite 插件生成 symbol。

阶段四不能把这类改造合入生产源码；只记录补丁和测量结果。

### Vuex 模块自动加载

管理端 `src/store/index.js` 使用 `require.context('./modules', true, /\.js$/)` 自动注册模块。Vite 下需要改为 `import.meta.glob('./modules/**/*.js', { eager: true })`。如果学生端没有同类模块自动加载，也应单独确认。

### publicPath 和后端 static

当前 `publicPath: './'` 是后端内置 static 部署的重要前提。Vite 必须使用 `base: './'`，并验证：

- 直接访问 `/admin/index.html`、`/student/index.html` 能加载相对 `static/` 资源。
- 刷新 hash 路由页面后不出现 404。
- 静态资源文件名 hash、CSS 中图片字体路径和 favicon 路径正常。

## 测量指标

每次试验至少记录以下指标，分别覆盖管理端和学生端：

- 冷启动耗时：执行 dev server 到首页可访问的时间。
- 首次页面可用时间：dev server 已启动后，浏览器打开首页到主界面可交互的时间。
- HMR 耗时：修改一个普通 `.vue` 文件后到浏览器更新的时间。
- 生产构建耗时：`vite build --mode prod` 或等价命令的 wall time。
- 构建产物体积：总大小、JS 总大小、CSS 总大小、最大 vendor chunk。
- 功能冒烟：登录、菜单跳转、列表查询、表单提交、Element 弹窗、进度条、图标显示。
- 管理端专项：UEditor 创建、编辑、公式、提交、回显。
- 部署冒烟：把 Vite 产物放入临时目录模拟 `/admin/`、`/student/` 相对路径访问，不同步到后端生产 static。

基线来自五阶段方案：

- 管理端 Vue CLI `npm run build:prod`：约 98 秒。
- 学生端 Vue CLI `npm run build:prod`：约 88 秒。

建议结果记录到 `.tmp/benchmarks/vite-spike-YYYYMMDD-HHMMSS.md`，不进入生产构建链路。

## 风险

- Vue 2 已 EOL，`@vitejs/plugin-vue2` 只能作为过渡工具，不能作为长期技术栈目标。
- `require.context`、Webpack loader、Vue CLI HTML 模板变量不会自动兼容 Vite。
- `process.env` 与 `import.meta.env` 差异可能影响接口 baseURL、静态资源 baseURL。
- UEditor 是全局脚本式资产，路径、加载顺序、弹窗 iframe 和公式插件都可能在 Vite dev server 下暴露问题。
- Element UI 2.x 不支持 Vue 3，阶段四继续保留它只用于验证构建工具收益。
- Vite 构建 chunk 拆分策略与 Vue CLI/Webpack 不同，可能改变缓存命中、首屏请求数和后端 static 体积。
- 若直接把 Vite 产物覆盖到 `source/xzs/src/main/resources/static`，会干扰当前生产构建验证，因此禁止。

## 回退方式

阶段四的回退标准很简单：删除临时 Vite 配置、临时依赖和临时输出目录，继续使用现有 Vue CLI 命令。

```powershell
cd source\vue\xzs-admin
npm run build:prod

cd ..\xzs-student
npm run build:prod
```

任何一项核心冒烟失败，都不推进替换：

- 登录或接口请求失败。
- SVG 图标大量缺失。
- 管理端 UEditor 不可用。
- 相对路径部署失败。
- 构建收益低于预期且引入明显兼容成本。

## 阶段四验收清单

- 文档记录管理端和学生端各自的 Vite 配置草案。
- 测量脚本只做检查和计时框架，不修改生产依赖。
- 试验结果同时包含耗时、体积、风险和失败项。
- 生产 `npm run build:prod` 仍是唯一发布入口。
- 阶段五 Vue 3 迁移方案接收阶段四发现的问题，不在阶段四扩大改造范围。
