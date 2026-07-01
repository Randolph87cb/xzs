# 微信小程序学生端结构

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

## 主要页面

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
