# 本地前端静态资源一致性防复发方案

## 背景与现状

- 已确认这次登录页仍提示“用户名不能少于 5 个字符”的直接原因不是源码未修改，而是本地服务实际读取了旧的 `source/xzs/target/classes/static/admin/static/LoginView-*.js`。
- 当前项目存在三类前端静态资源位置：
  - Vite 构建输出：`frontend/apps/admin/admin`、`frontend/apps/student/student`。
  - 后端源码资源：`source/xzs/src/main/resources/static/admin|student`。
  - Spring Boot 运行目录：`source/xzs/target/classes/static/admin|student`。
- `scripts/sync-web-static.ps1` 之前只覆盖 `src/main/resources/static`，没有覆盖已经运行中的 `target/classes/static`。因此后端不重启或 Maven 不重新复制资源时，页面仍可能读旧 bundle。
- 提交记录显示类似问题已经出现过：
  - `86b10c81 修复前端静态资源映射`：修正 URL 到 classpath 静态目录的映射。
  - `1542497f 自动使用本地前端静态资源`：在 `dev` profile 下直接读本地前端构建目录。
  - `488ce7d3 同步前端静态资源到运行目录`：补上同步到 `target/classes/static`。
- 关键缺口是：本地 Neon test branch 启动使用的是 `prod` profile，不会走 `1542497f` 加的 dev 直读本地前端目录逻辑，仍然依赖 classpath 静态资源。

## 结论

推荐把“本地启动时前端静态资源来源”改成自动、可验证的流程：新增一个本地 Neon 启动脚本作为唯一入口，启动前构建/同步/校验静态资源；同时给后端增加显式的本地静态资源模式，让 Neon test branch 即使使用 prod 配置，也可以在本地直接读取 Vite 构建输出，减少 `target/classes/static` 残留造成的旧页面问题。

## 需求拆解

### 1. 统一本地启动入口

- 当前现状：
  - 现在可以手动执行 `.env.neon-test` 加载、`mvnw spring-boot:run`、前端 build、`sync-web-static.ps1`，但这些步骤是分散的。
  - 一旦漏掉同步或后端运行目录未更新，页面就会读旧 bundle。
- 判断：
  - 防复发不能靠“记得同步”，需要启动脚本把顺序固定下来。
- 修改方案：
  - 新增 `scripts/start-local-neon.ps1`，作为本地 Neon test branch 开发服务的唯一推荐入口。
  - 脚本职责：
    - 加载 `.env.neon-test`，不打印敏感配置。
    - 设置本地绕过代理变量，例如 `NO_PROXY=localhost,127.0.0.1,::1`。
    - 可选执行 `pnpm --filter @xzs/admin build` 和 `pnpm --filter @xzs/student build`。
    - 执行 `scripts/sync-web-static.ps1`。
    - 执行静态资源一致性校验。
    - 启动 `source/xzs` 的 `mvnw spring-boot:run`。
  - 支持参数：
    - `-SkipBuild`：只同步和启动，用于刚构建过的场景。
    - `-SkipSync`：仅在确认使用本地静态直读模式时允许。
    - `-NoRestart` 或 `-CheckOnly`：只跑校验不启动。
- 影响范围：
  - `scripts/start-local-neon.ps1`
  - `AGENTS.md` 本地启动规则
- 验证方案：
  - 通过该脚本启动后，`http://127.0.0.1:8000/admin/index.html` 和学生端入口返回 200。
  - 修改登录页文案后运行脚本，不需要人工找 `target/classes/static`，页面能加载新 bundle。

### 2. 增加显式本地静态资源模式

- 当前现状：
  - `WebMvcConfiguration` 只有 `dev` profile 才走本地文件目录：
    - `frontend/apps/admin/admin`
    - `frontend/apps/student/student`
  - `.env.neon-test` 当前启动 profile 是 `prod`，所以仍走 `classpath:/static/`。
- 判断：
  - profile 不应该承担“数据库环境”和“静态资源来源”两种职责。Neon test branch 可以继续用生产数据库配置风格，但本地静态资源应由显式开关控制。
- 修改方案：
  - 在 `WebMvcConfiguration` 中新增属性判断，例如：
    - `xzs.web.static.use-local=true`
    - 或 `XZS_WEB_STATIC_USE_LOCAL=true`
  - `isDevProfile() || useLocalStatic()` 时走 `addDevResourceHandlers`。
  - 本地启动脚本设置 `XZS_WEB_STATIC_USE_LOCAL=true`，让后端直接读取 Vite 构建输出目录。
  - 生产部署不设置该变量，仍使用 classpath 静态资源。
- 影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/configuration/spring/mvc/WebMvcConfiguration.java`
  - `source/xzs/src/main/resources/application-dev.yml`
  - `scripts/start-local-neon.ps1`
- 验证方案：
  - 在 `prod` profile + `XZS_WEB_STATIC_USE_LOCAL=true` 下，请求 `/admin/index.html` 返回的入口脚本名和 `frontend/apps/admin/admin/index.html` 一致。
  - 在不设置该变量的普通 prod 启动下，仍使用 classpath 静态资源，不影响打包部署。

### 3. 静态资源一致性校验自动失败

- 当前现状：
  - `scripts/verify-admin-static.ps1` 只检查 `src/main/resources/static/admin` 是否像 Vite 输出，并请求页面是否像 Vite 构建。
  - 它没有比较“源码资源、运行目录、实际 HTTP 响应”是否是同一版。
- 判断：
  - 需要用机器可判断的证据确认当前服务没有读旧 bundle。
- 修改方案：
  - 新增或扩展校验脚本，例如 `scripts/verify-web-static-consistency.ps1`。
  - 校验项：
    - 解析 `frontend/apps/admin/admin/index.html`、`source/xzs/src/main/resources/static/admin/index.html`、`source/xzs/target/classes/static/admin/index.html` 的入口 JS 文件名。
    - 三者入口 JS 必须一致；如果 `target/classes/static` 不存在，则提示先 package 或 sync。
    - 对学生端做同样检查。
    - 请求 `http://127.0.0.1:8000/admin/index.html` 和 `/student/index.html`，确认 HTTP 返回的入口 JS 文件名和本地构建输出一致。
    - 可选支持 `-ForbiddenText`，用于检查某些已删除文案不会再出现在运行目录 bundle 中。
  - `scripts/start-local-neon.ps1` 启动前后都调用该脚本；验证失败则直接停止，不给出“服务已启动”的结论。
- 影响范围：
  - `scripts/verify-web-static-consistency.ps1`
  - `scripts/start-local-neon.ps1`
  - 可选替换/调用 `scripts/verify-admin-static.ps1`
- 验证方案：
  - 人为放入旧 `target/classes/static/admin/index.html`，脚本能失败并指出不一致路径。
  - 正常同步后脚本通过。
  - 后端启动后，HTTP 响应和本地构建输出一致。

### 4. 构建和同步脚本职责收敛

- 当前现状：
  - `build-admin.ps1` 和 `build-student.ps1` 只构建 Vite，不同步。
  - `build-all.ps1` 会调用 `sync-web-static.ps1`。
  - 单独跑前端 build 后，如果不再同步，后端运行目录仍可能过期。
- 判断：
  - 单独构建脚本保持“只构建”是合理的，但需要给本地联调一个包含 build + sync + verify 的组合入口。
- 修改方案：
  - 保持 `build-admin.ps1` / `build-student.ps1` 不自动同步，避免改变 CI/打包语义。
  - 在 `start-local-neon.ps1` 和 `build-all.ps1` 中明确执行 `sync-web-static.ps1` 和一致性校验。
  - `sync-web-static.ps1` 保持当前修复：同时同步 `src/main/resources/static` 和存在时的 `target/classes/static`。
  - 在脚本输出中明确写出两个目标目录，方便发现漏同步。
- 影响范围：
  - `scripts/build-all.ps1`
  - `scripts/sync-web-static.ps1`
  - `scripts/start-local-neon.ps1`
- 验证方案：
  - 单独 `build-admin.ps1` 后校验脚本能发现后端目录未同步。
  - `build-all.ps1` 后校验脚本通过。
  - `start-local-neon.ps1` 后页面加载最新 bundle。

### 5. 文档和项目规则防复发

- 当前现状：
  - `AGENTS.md` 说明了本地使用 Neon test branch，但没有强制说明“启动必须走统一脚本”。
  - 之前问题靠人工发现和截图反馈。
- 判断：
  - 需要把约束写进项目规则，让后续 AI 或人工都走同一流程。
- 修改方案：
  - 更新 `AGENTS.md`：
    - 本地启动后端必须优先使用 `scripts/start-local-neon.ps1`。
    - 不要直接裸跑 `mvnw spring-boot:run`，除非明确说明已经完成静态资源一致性校验。
    - 修改前端后要运行 `scripts/verify-web-static-consistency.ps1` 或通过统一启动脚本自动运行。
  - 更新 `docs/project-structure/frontend-modernization.md` 或新增本地开发说明，解释三类静态目录的职责。
- 影响范围：
  - `AGENTS.md`
  - `docs/project-structure/frontend-modernization.md`
  - 本文档
- 验证方案：
  - 新开线程或后续任务读取 `AGENTS.md` 时，能明确知道不能裸启动。
  - 任何前端页面修改后的最终验收必须包含 HTTP 页面入口和 bundle 一致性检查。

## 执行顺序

1. 新增 `scripts/verify-web-static-consistency.ps1`，先让旧资源问题可以被自动检测出来。
2. 新增 `scripts/start-local-neon.ps1`，把加载 Neon env、构建、同步、校验、启动串起来。
3. 改造 `WebMvcConfiguration`，增加 `xzs.web.static.use-local` 显式本地静态资源开关。
4. 让 `start-local-neon.ps1` 默认启用本地静态资源直读；保留 `sync-web-static.ps1` 作为 classpath/static 打包和兜底同步。
5. 更新 `build-all.ps1`，在 sync 后调用一致性校验。
6. 更新 `AGENTS.md` 和项目结构文档，把统一启动入口写成规则。
7. 用一次真实流程验证：修改登录页临时文案、构建、统一启动、HTTP 校验、浏览器刷新，确认不会读旧 bundle。

## 风险与待确认

- 待确认：本地 Neon test branch 是否必须保持 `SPRING_PROFILES_ACTIVE=prod`。如果必须保持，就使用 `XZS_WEB_STATIC_USE_LOCAL=true` 独立控制静态资源来源；如果可以改成 `dev` profile，则可以复用已有 dev 静态直读逻辑，但要避免 dev 数据库配置覆盖 Neon 配置。
- 风险：直接读取 Vite 构建输出目录要求先执行前端 build，否则目录不存在或仍是旧构建。统一启动脚本默认应先 build，除非显式 `-SkipBuild`。
- 风险：生产构建不能依赖本地文件目录。`xzs.web.static.use-local` 必须默认 false，只由本地脚本设置。
- 风险：浏览器缓存仍可能保留旧 hash chunk，但 Vite 入口文件 hash 改变后通常会加载新 chunk。校验脚本以服务端 HTTP 响应为准，若用户浏览器仍旧，需要提示 Ctrl+F5。
