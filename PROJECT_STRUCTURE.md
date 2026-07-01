# 项目结构说明

本文档基于当前仓库代码梳理，帮助新参与者快速定位后端、Web 前端、微信小程序、数据库与部署资产。

## 项目概览

学之思开源考试系统 PostgreSQL 版，整体是 Java + Vue 的前后端分离考试系统，并附带微信小程序学生端。仓库同时包含源码、静态文档站、数据库脚本、Docker 配置和已构建发布包。

主要技术栈：

- 后端：Java 8、Spring Boot 2.1.6、Spring Security、MyBatis、PageHelper、Undertow、PostgreSQL。
- Web 前端：Vue 2.7、Vue Router 3、Vuex 3、Element UI、Axios、Vue CLI 4。
- 微信小程序：原生微信小程序，内置 iView Weapp 组件。
- 数据库：PostgreSQL 脚本位于 `sql/xzs-postgresql.sql`。

## 顶层目录

```text
xzs/
├── docker/              # Docker 部署材料，包含 compose、安装文件和发布 jar
├── docs/                # 已构建的项目文档站静态文件
├── release/             # 已构建发布包：后端 jar 与前端静态包
├── source/              # 源码根目录
│   ├── xzs/             # Spring Boot 后端
│   ├── vue/             # Web 前端源码
│   │   ├── xzs-admin/   # 管理端 Vue 项目
│   │   └── xzs-student/ # 学生端 Vue 项目
│   └── wx/              # 微信小程序源码
│       └── xzs-student/ # 学生端小程序
├── sql/                 # PostgreSQL 建库/建表/初始化脚本
├── README.md            # 项目介绍、功能说明与外部文档链接
└── LICENSE              # AGPL-3.0
```

## 后端结构

后端工程位于 `source/xzs`，Maven 坐标为 `com.mindskip:xzs:3.9.0`，打包类型为 jar。启动类是 `source/xzs/src/main/java/com/mindskip/xzs/XzsApplication.java`。

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
        ├── mapper/           # MyBatis XML SQL 映射
        └── static/           # 集成部署时内置的 admin/student 静态页面
```

后端主要 API 前缀：

- 管理端：`/api/admin/...`，对应 `controller/admin`。
- 学生 Web 端：`/api/student/...`，对应 `controller/student`。
- 微信小程序：`/api/wx/student/...`，对应 `controller/wx/student`。

核心业务实体集中在 `domain`，包括用户、科目、题目、试卷、答卷、消息、任务、用户日志和 token。数据访问接口在 `repository`，SQL 实现在 `resources/mapper/*.xml`，业务编排在 `service/impl`。

默认后端端口是 `8000`。`application.yml` 启用 `dev` profile；各环境 datasource 默认指向 `jdbc:postgresql://localhost:5432/xzs`，用户名 `postgres`，密码 `123456`。

## 管理端 Vue 项目

管理端位于 `source/vue/xzs-admin`，构建输出目录为 `admin`，开发端口为 `8002`，开发代理将 `/api` 转发到 `http://localhost:8000`。

```text
source/vue/xzs-admin/
├── package.json
├── vue.config.js
├── public/
└── src/
    ├── api/          # 后端 API 封装：用户、试卷、题目、任务、消息等
    ├── assets/       # 图片与 Element UI 自定义主题
    ├── components/   # 分页、富文本、面包屑、图标等通用组件
    ├── icons/        # svg-sprite 图标
    ├── layout/       # 后台布局、侧边栏、导航、标签页
    ├── store/        # Vuex 模块
    ├── styles/       # 全局样式与主题变量
    ├── utils/        # Axios 请求封装、工具函数、校验
    ├── views/        # 页面
    ├── main.js
    ├── App.vue
    └── router.js
```

主要页面模块：

- `views/dashboard`：后台首页统计。
- `views/user`：学生与管理员管理。
- `views/exam/paper`：试卷列表与编辑。
- `views/exam/question`：题目列表与单选、多选、判断、填空、简答题编辑。
- `views/task`：任务列表与编辑。
- `views/education/subject`：学科管理。
- `views/answer`：答卷记录。
- `views/message`：消息列表与发送。
- `views/log`：用户日志。
- `views/profile`：个人资料。

## 学生端 Vue 项目

学生 Web 端位于 `source/vue/xzs-student`，构建输出目录为 `student`，开发端口为 `8001`，开发代理同样将 `/api` 转发到 `http://localhost:8000`。

```text
source/vue/xzs-student/
├── package.json
├── vue.config.js
├── public/
└── src/
    ├── api/          # 学生端 API 封装
    ├── assets/       # 首页轮播、考试说明、主题与图标资源
    ├── components/   # 分页、富文本、返回顶部等通用组件
    ├── icons/        # svg-sprite 图标
    ├── layout/       # 学生端整体布局
    ├── store/        # Vuex 模块
    ├── styles/       # 全局样式
    ├── utils/        # Axios 请求封装与工具函数
    ├── views/        # 页面
    ├── main.js
    ├── App.vue
    └── router.js
```

主要页面模块：

- `views/dashboard`：学生首页与任务入口。
- `views/paper`：试卷列表。
- `views/exam/paper`：答题、批改、查看试卷。
- `views/record`：考试记录。
- `views/question-error`：错题本。
- `views/user-info`：个人信息与消息。
- `views/login`、`views/register`：登录注册。

## 微信小程序

小程序学生端位于 `source/wx/xzs-student`，入口文件为 `app.js`、`app.json`、`app.wxss`。`app.js` 中的 `globalData.baseAPI` 默认是 `http://localhost:8000`，请求统一走 `formPost`，使用本地存储 token。

```text
source/wx/xzs-student/
├── app.js
├── app.json
├── app.wxss
├── project.config.json
├── assets/       # 小程序图片资源
├── component/    # 内置 iView Weapp 组件
├── pages/        # 小程序页面
├── utils/        # 工具与百度统计 SDK
└── wxs/          # WXS 脚本
```

主要页面：

- `pages/index/index`：首页。
- `pages/exam/index`：试卷列表。
- `pages/exam/do`：答题。
- `pages/exam/edit`：批改。
- `pages/exam/read`：查看试卷。
- `pages/record/index`：记录。
- `pages/my/index`：我的。
- `pages/my/info`：个人信息。
- `pages/my/message`：消息列表与详情。
- `pages/my/log`：个人动态。
- `pages/user/bind`：微信绑定登录。
- `pages/user/register`：注册。

## 数据库与部署资产

`sql/xzs-postgresql.sql` 是 PostgreSQL 初始化脚本，包含序列、表结构和初始化数据。`sql/README.md` 只保留数据库下载地址说明。

`release` 目录保存已构建产物：

- `release/java/xzs-3.9.0.jar`：后端 jar。
- `release/web/admin`：管理端静态资源。
- `release/web/student`：学生端静态资源。

`docker` 目录保存 Docker 部署材料：

- `docker/docker-compose.yml`：compose 配置。
- `docker/release/xzs-3.9.0.jar`：Docker 部署使用的 jar。
- `docker/install/docker-compose-linux-x86_64`：附带的 docker-compose 二进制。

注意：当前仓库 README、后端配置和 SQL 文件均指向 PostgreSQL 版，但 `docker/docker-compose.yml` 与 `docker/README.md` 中仍出现 MySQL 镜像和 MySQL 部署说明。使用 Docker 部署前需要按目标数据库版本核对 compose、SQL 脚本和后端 datasource。

## 常用命令

后端本地运行：

```powershell
cd source\xzs
.\mvnw.cmd spring-boot:run
```

后端打包：

```powershell
cd source\xzs
.\mvnw.cmd clean package
```

管理端开发：

```powershell
cd source\vue\xzs-admin
npm install
npm run serve
```

学生端开发：

```powershell
cd source\vue\xzs-student
npm install
npm run serve
```

管理端/学生端构建：

```powershell
npm run build
```

集成部署时，将管理端构建产物 `admin` 和学生端构建产物 `student` 放到 `source/xzs/src/main/resources/static` 后，再打包后端 jar。

## 阅读入口建议

如果要理解一次完整业务链路，可以按以下顺序阅读：

1. Web 路由：`source/vue/xzs-admin/src/router.js` 或 `source/vue/xzs-student/src/router.js`。
2. 页面组件：对应 `views` 目录下的 `.vue` 文件。
3. 前端 API：对应 `src/api/*.js`。
4. 后端 Controller：对应 `source/xzs/src/main/java/com/mindskip/xzs/controller`。
5. Service 实现：对应 `source/xzs/src/main/java/com/mindskip/xzs/service/impl`。
6. Mapper 与 SQL：`source/xzs/src/main/java/com/mindskip/xzs/repository` 和 `source/xzs/src/main/resources/mapper`。
7. 实体与 VM：`domain` 和 `viewmodel`。
