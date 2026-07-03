# 管理端 Vue 项目结构

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
    ├── plugins/      # Element UI 等 Vue 插件按需注册入口
    ├── store/        # Vuex 模块
    ├── styles/       # 全局样式与主题变量
    ├── utils/        # Axios 请求封装、工具函数、校验
    ├── views/        # 页面
    ├── main.js
    ├── App.vue
    └── router.js
```

## 主要页面模块

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

## 常用命令

```powershell
cd source\vue\xzs-admin
npm install
npm run serve
```

```powershell
cd source\vue\xzs-admin
npm run build
```

或从仓库根目录运行：

```powershell
.\scripts\build-admin.ps1 -SkipInstall
```
