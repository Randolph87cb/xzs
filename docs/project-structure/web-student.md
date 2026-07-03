# 学生端 Vue 项目结构

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
    ├── plugins/      # Element UI 等 Vue 插件按需注册入口
    ├── store/        # Vuex 模块
    ├── styles/       # 全局样式
    ├── utils/        # Axios 请求封装与工具函数
    ├── views/        # 页面
    ├── main.js
    ├── App.vue
    └── router.js
```

## 主要页面模块

- `views/dashboard`：学生首页与任务入口。
- `views/paper`：试卷列表。
- `views/exam/paper`：答题、批改、查看试卷。
- `views/record`：考试记录。
- `views/question-error`：错题本。
- `views/user-info`：个人信息与消息。
- `views/login`、`views/register`：登录注册。

## 常用命令

```powershell
cd source\vue\xzs-student
npm install
npm run serve
```

```powershell
cd source\vue\xzs-student
npm run build
```

或从仓库根目录运行：

```powershell
.\scripts\build-student.ps1 -SkipInstall
```
