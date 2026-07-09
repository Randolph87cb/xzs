# 后端结构

后端工程位于 `source/xzs`，Maven 坐标为 `com.mindskip:xzs:3.9.0`，打包类型为 jar。启动类是 `source/xzs/src/main/java/com/mindskip/xzs/XzsApplication.java`。当前后端技术栈已升级到 Spring Boot 2.7.18，并引入 Flyway 管理 PostgreSQL schema 迁移。

```text
source/xzs/
├── pom.xml
├── mvnw / mvnw.cmd
└── src/main/
    ├── java/com/mindskip/xzs/
    │   ├── XzsApplication.java
    │   ├── base/             # 通用 Controller、分页、响应对象、系统状态码
    │   ├── configuration/    # Spring MVC、安全、异常处理、属性配置、微信拦截器
    │   ├── context/          # Web 与微信请求上下文
    │   ├── controller/       # 管理端、学生端、小程序 API
    │   ├── domain/           # 数据库实体、枚举、题目/试卷/任务 JSON 对象
    │   ├── event/            # 注册、用户日志、答卷计算事件
    │   ├── exception/        # 业务异常
    │   ├── listener/         # 事件监听器
    │   ├── repository/       # MyBatis Mapper 接口
    │   ├── service/          # 业务服务接口与实现
    │   ├── utility/          # 日期、JSON、分页、RSA、微信等工具类
    │   └── viewmodel/        # admin/student/wx 的请求与响应 VM
    └── resources/
        ├── application.yml
        ├── application-dev.yml
        ├── application-test.yml
        ├── application-pre.yml
        ├── application-prod.yml
        ├── db/migration/     # Flyway 数据库迁移脚本，当前包含 V1 基线迁移
        ├── mapper/           # MyBatis XML SQL 映射
        └── static/           # 集成部署时内置的 admin/student 静态页面
```

## API 前缀

- 管理端：`/api/admin/...`，对应 `controller/admin`。
- 学生 Web 端：`/api/student/...`，对应 `controller/student`。
- 微信小程序：`/api/wx/student/...`，对应 `controller/wx/student`。

## 关键分层

- `domain`：用户、科目、题目、试卷、答卷、消息、任务、用户日志和 token 等核心实体。
- `repository`：MyBatis Mapper 接口。
- `resources/mapper/*.xml`：SQL 映射实现。
- `resources/db/migration/*.sql`：Flyway 迁移脚本；当前 `V1__baseline_schema.sql` 来自 PostgreSQL 初始化脚本，用于空库初始化和已有库基线接入。
- `service/impl`：业务编排与核心逻辑。
- `viewmodel`：按 `admin`、`student`、`wx` 拆分的请求与响应模型。

默认后端端口是 `8000`。`application.yml` 启用 `dev` profile；各环境 datasource 默认指向 `jdbc:postgresql://localhost:5432/xzs`，用户名 `postgres`，密码 `123456`。
Flyway 默认从 `classpath:db/migration` 加载迁移脚本，并通过 `spring.flyway.*` 配置控制基线、校验和清理保护策略。

## 常用命令

```powershell
cd source\xzs
.\mvnw.cmd spring-boot:run
```

```powershell
cd source\xzs
.\mvnw.cmd clean package
```
