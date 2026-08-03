# 微信小程序学生端结构

> 状态：历史源码保留，当前停用。

小程序学生端位于 `source/wx/xzs-student`，当前不启用、不构建、不发布、不验收，也不作为现行产品能力。默认开发、构建、部署和验收只覆盖学生 Web 与管理 Web；除非用户明确要求重新启用，不为小程序同步新功能。

源码与后端 `/api/wx/**` 兼容接口均继续保留，不删除。历史入口文件为 `app.js`、`app.json`、`app.wxss`；`app.js` 中的 `globalData.baseAPI` 默认是 `http://localhost:8000`，请求统一走 `formPost`，使用本地存储 token。

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

## 历史主要页面

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
