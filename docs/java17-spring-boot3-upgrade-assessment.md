# Java 17 与 Spring Boot 3 升级预研评估

评估日期：2026-07-09

## 结论摘要

本报告是技术架构升级 harness 阶段 5 的预研产出，只评估 Java 17 与 Spring Boot 3 的升级风险和迁移路线，不代表当前阶段启动生产代码改造。本阶段不修改 `pom.xml`、Java 源码或部署脚本。

当前不建议近期直接启动生产升级。更稳妥的做法是先在独立临时分支完成一次可丢弃的探针升级，验证编译、启动、安全登录、分页查询、Flyway、Docker 镜像和树莓派内存占用后，再决定是否进入正式迁移阶段。

## 目标

- 评估从当前 Spring Boot 2.7.x、Java 8 编译目标迁移到 Java 17 与 Spring Boot 3 的主要破坏性变化。
- 明确后端代码、依赖、测试、Docker 镜像和树莓派部署的风险点。
- 给出推荐迁移步骤、测试策略和回退策略。
- 判断是否建议近期启动生产改造。

## 非目标

- 不在本阶段升级生产代码。
- 不修改 `source/xzs/pom.xml`。
- 不修改 Java 源码、配置文件或部署脚本。
- 不要求产出可运行的 Spring Boot 3 分支。
- 不顺带重构业务功能、数据库 schema、前端或微信小程序。

## 当前已完成前置条件

- Spring Boot 2.7：后端 `pom.xml` 当前已使用 Spring Boot `2.7.18`，相较早期 2.1 已先完成小版本安全升级。
- Flyway：后端已引入 `flyway-core`，`application.yml` 中已配置 `spring.flyway.*`，并已有 `docs/database-migration-flyway.md` 记录基线迁移策略。
- 健康检查：后端已引入 Actuator，`application.yml` 暴露 `health`，忽略路径包含 `/actuator/health`。
- 树莓派部署资产：已有 `docs/raspberry-pi-deployment.md`，并已有 `deploy/raspberry-pi/xzs.service`、`init-db.sh`、`backup-db.sh`、`restore-db.sh`；文档记录了低资源 JVM、Undertow 和 Hikari 参数。

这些前置条件降低了未来升级的不确定性，但不能抵消 Spring Boot 3 的包名、框架 API 和依赖兼容性破坏。

## 主要破坏性变化

### Java 17 基线

Spring Boot 3 要求 Java 17 或更高版本运行。当前后端仍配置 `maven.compiler.source`、`maven.compiler.target` 和 `java.version` 为 `1.8`，Docker 构建与运行镜像也基于 Eclipse Temurin 8。正式升级需要同时调整 Maven 编译目标、开发机 JDK、CI 或本地构建环境、Docker build stage 和 runtime stage。

### `javax.*` 到 `jakarta.*`

Spring Boot 3 基于 Spring Framework 6 和 Jakarta EE，Servlet、Validation 等 API 从 `javax.*` 迁移到 `jakarta.*`。当前主源码初步识别到 87 处 `javax.*` 导入，主要包括：

- `javax.servlet.*`、`javax.servlet.http.*`：安全过滤器、登录/登出处理器、拦截器、控制器错误处理等路径受影响。
- `javax.validation.*`：请求 VM、校验注解和 `@Valid` 受影响。

这不是简单替换包名即可完成的低风险改动，因为相关第三方依赖也必须同时支持 Jakarta。

### Spring Security 6 配置模型

当前安全配置仍使用 `WebSecurityConfigurerAdapter`、`authorizeRequests()`、`antMatchers()`、链式 `.and()` 风格以及自定义登录过滤器。Spring Security 6 中这些旧写法需要迁移到 `SecurityFilterChain` Bean、`authorizeHttpRequests()`、`requestMatchers()` 和新的 DSL 风格。

风险重点：

- 自定义 `RestLoginAuthenticationFilter` 依赖 `authenticationManagerBean()`，正式迁移时需要明确 `AuthenticationManager` 的 Bean 来源。
- 角色授权、忽略路径、CORS、CSRF、remember-me、异常处理和退出登录都需要行为回归测试。
- `/actuator/health`、微信端匿名接口、学生注册接口必须继续允许匿名访问。

### ErrorController 与错误处理

当前 `ErrorController` 继承 `BasicErrorController`，直接构造 `DefaultErrorAttributes` 和 `ErrorProperties`，并使用 `javax.servlet.http.HttpServletRequest`。Spring Boot 3 下包名需要迁移，错误属性和自动配置行为也需要复核。

风险重点：

- 自定义全局错误响应当前固定返回 HTTP 200 和业务错误码，升级后需要确认静态资源 404、API 500、登录失效、权限不足不会被新错误处理链绕开。
- `BasicErrorController` 继承式覆盖较脆，建议在正式迁移时评估是否改为更明确的 `ErrorAttributes` 或 `@ControllerAdvice` 方案，但不应在探针阶段扩展业务行为。

### MyBatis 与 PageHelper

当前依赖包括 `mybatis-spring-boot-starter:2.1.0` 和 `pagehelper-spring-boot-starter:1.2.12`。这两者版本偏旧，不能默认认为兼容 Spring Boot 3。

风险重点：

- MyBatis Spring Boot Starter 需要升级到支持 Spring Boot 3 / Jakarta 的主线版本。
- PageHelper starter 需要确认是否支持 Boot 3 的自动配置机制和依赖版本。
- Mapper XML、分页插件、事务、数据源自动配置和 PostgreSQL 方言需要重点测试。

### Undertow

当前应用排除了 Tomcat，使用 `spring-boot-starter-undertow`，并通过环境变量控制 Undertow 线程、buffer 和 direct buffer。Spring Boot 3 的 Undertow 版本基于 Jakarta Servlet，相关 servlet API 包名变化会影响自定义过滤器、处理器和拦截器。

风险重点：

- 低资源参数是否仍被 Boot 3 正确绑定。
- direct buffer、线程数和压缩配置在树莓派上是否造成额外内存压力。
- 静态资源、API、Actuator 和错误页在 Undertow 下都需要实际启动验收。

### JUnit 4 与测试平台

当前测试依赖显式保留 `junit:junit` 和 `junit-vintage-engine`，源码测试中初步识别到 15 处 JUnit 4 导入。Spring Boot 3 仍可通过 Vintage 运行部分 JUnit 4 测试，但推荐迁移到 JUnit Jupiter。

风险重点：

- 继续保留 Vintage 会延长迁移期并隐藏旧测试模式问题。
- Spring Security 测试、MockMvc、过滤器测试和 controller 测试需要确认是否仍按预期加载安全链。
- 当前 `skipTests=true` 会削弱升级反馈，正式迁移前必须让关键测试在 CI 或本地验证入口中可执行。

### Flyway

Boot 3 管理的 Flyway 版本会明显高于当前 Boot 2.7 组合。现有基线策略包括 `baseline-on-migrate=true`、`validate-on-migrate=true` 和 `clean-disabled=true`，方向正确，但升级后仍需复核：

- PostgreSQL 驱动版本与 Flyway 版本兼容性。
- 已有库 baseline 记录是否仍被正确识别。
- 空库初始化和已有库启动的差异。
- 迁移校验失败时应用是否按预期启动失败。

### Java 17 构建与 Docker 镜像

当前 Dockerfile 后端构建镜像为 `maven:3.8.8-eclipse-temurin-8`，运行镜像为 `eclipse-temurin:8-jre`。Boot 3 升级需要至少改为 JDK/JRE 17，例如构建阶段使用 Maven + Temurin 17，运行阶段使用 Temurin 17 JRE 或 JDK 运行时镜像。

风险重点：

- 镜像体积和冷启动时间可能上升，需要重新测量 Fly.io 和树莓派场景。
- Maven 编译目标、依赖插件、Spring Boot Maven Plugin 行为需要一起验证。
- 若未来采用 distroless 或 jlink 精简镜像，应作为单独优化阶段，不与 Boot 3 迁移混在一起。

### 树莓派运行内存影响

Java 17、Spring Boot 3、Spring Framework 6 和新依赖可能提升基础内存占用。树莓派部署当前建议 `-Xms128m -Xmx512m -XX:+UseSerialGC`，并降低 Undertow 和 Hikari 参数。正式迁移前必须在目标设备或等价低资源环境测量：

- 空闲 RSS、堆使用、direct memory 和线程数。
- 首次启动时间与健康检查可用时间。
- 登录、列表分页、考试提交等高频路径的峰值内存。
- PostgreSQL 与 JVM 同机运行时是否触发 swap。

## 代码风险点

- `javax.servlet` 与 `javax.validation` 导入面较广，涉及安全、控制器、拦截器和 VM 校验对象。
- Spring Security 配置集中在自定义过滤器链，迁移后容易出现匿名接口被拦、权限放宽或登录状态失效。
- 自定义错误处理继承 Boot 内部控制器，升级后需要重新确认默认错误路由和 JSON 响应行为。
- 静态资源路径、管理端和学生端入口依赖后端 Web 层配置，升级 Undertow 和错误处理时要一起验收。
- Java 17 更严格的反射、非法访问和编码差异可能影响旧工具类、ModelMapper、RSA 工具或 JSON 绑定边界。

## 依赖风险点

- `mybatis-spring-boot-starter:2.1.0` 需要升级到支持 Boot 3 的版本线。
- `pagehelper-spring-boot-starter:1.2.12` 需要确认 Boot 3 兼容版本及自动配置变更。
- `modelmapper:2.3.3`、`commons-pool2:2.6.1`、`httpclient:4.5.9` 等旧依赖需要做 Java 17 运行兼容性复核。
- PostgreSQL JDBC 驱动当前为 `42.2.28`，建议在 Boot 3 探针分支中升级到更近版本并回归连接、时区和 SQL 类型映射。
- Flyway 版本由 Boot 3 管理后，已有 baseline 策略要在空库和非空库分别验证。
- Undertow starter 继续可用，但所有 servlet 相关扩展必须迁移到 Jakarta API。

## 测试策略

正式生产升级前建议至少覆盖以下验证层级：

- 编译层：Java 17 下完整后端编译，测试编译必须打开。
- 单元测试层：过滤器、工具类、题库导入、分页转换等现有测试通过，并逐步迁移 JUnit 4 到 JUnit Jupiter。
- Web 层：MockMvc 或等价测试覆盖登录、登出、权限不足、匿名接口、学生端和管理端授权路径。
- 数据层：MyBatis mapper、PageHelper 分页、事务提交/回滚、PostgreSQL 连接池配置。
- Flyway：空库初始化、已有库 baseline、迁移校验失败场景。
- 启动层：dev/prod profile 启动，`/actuator/health` 可访问，静态入口可访问。
- Docker 层：Java 17 镜像构建、容器启动、环境变量覆盖、健康检查。
- 树莓派层：systemd 启动、内存峰值、swap、数据库备份恢复脚本与应用共存压力。

本阶段按要求不运行验证命令；上述为后续验证 subagent 或正式迁移阶段的验证清单。

## 推荐迁移步骤

1. 建立临时探针分支或一次性工作树，禁止直接在主线生产改造。
2. 先只调整 Java 17 构建基线：Maven compiler、开发 JDK、Docker 构建镜像和运行镜像。
3. 升级 Spring Boot 到 3.x，并同步 Spring Security、MyBatis、PageHelper、PostgreSQL JDBC、Flyway 等兼容版本。
4. 批量迁移 `javax.*` 到 `jakarta.*`，同时处理依赖不兼容导致的编译错误。
5. 将 Spring Security 从 `WebSecurityConfigurerAdapter` 改为 `SecurityFilterChain`，保持现有权限规则不扩展。
6. 修复 `ErrorController` 和错误处理链，确保 API 错误响应、静态资源和权限错误行为可解释。
7. 打开测试编译和关键测试，优先补齐安全链、分页、Flyway 和健康检查回归。
8. 构建 Java 17 Docker 镜像，分别在本地容器、Fly.io 类似环境和树莓派低资源环境做启动与内存测量。
9. 根据探针结果拆分正式迁移任务，明确每个任务的写入范围、验证入口和回退点。

## 回退策略

- 探针阶段：直接丢弃临时分支或工作树，不影响当前 Boot 2.7 主线。
- 正式迁移阶段：每个提交只覆盖一类变化，例如 Java 17 基线、Jakarta 包名、安全配置、依赖升级、Docker 镜像，便于逐步回退。
- 数据库：Boot 3 升级不应引入业务 schema 变更；Flyway 迁移文件一旦进入共享环境不得改写。出现生产风险时优先回退应用镜像和 Jar，数据库保持兼容。
- 部署：保留 Java 8 / Boot 2.7 的上一版 Jar、Docker 镜像、systemd 配置和数据库备份，升级窗口内可快速切回。
- 树莓派：如内存不达标，优先回退应用版本，再单独评估 JVM 参数、镜像精简或拆分数据库部署，不在现场临时扩大代码改造范围。

## 是否建议近期启动

不建议近期直接启动生产改造。建议先完成一次严格隔离的探针升级，并把探针结果沉淀为正式迁移计划。

原因：

- `javax.* -> jakarta.*` 和 Spring Security 6 迁移会触及登录、权限和请求处理主链路。
- MyBatis、PageHelper、Undertow、Flyway 和 JUnit 4 都存在依赖兼容性或验证缺口。
- 当前 Docker 与树莓派资产仍基于 Java 8 运行假设，Java 17 的镜像体积、启动时间和内存占用需要重新测量。
- 当前前置阶段刚完成 Boot 2.7、Flyway、健康检查和树莓派部署资产，短期内更应该先稳定这些成果。

建议的近期动作是：保留主线在 Spring Boot 2.7，启动一个只读评估加临时分支探针任务；只有当编译、启动、核心接口、Flyway、Docker 和树莓派内存验收都通过后，再进入生产迁移设计。
