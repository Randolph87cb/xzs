# 前端覆盖式重构阶段 7 管理端题库与 UEditor 闭环报告

## 阶段范围

阶段 7 聚焦管理端题库编辑的最小闭环，目标是让 Vue 3 管理端可以进入题库列表、预览题目、打开题目编辑页、加载 UEditor、保存题干和解析，并用统一 `question-renderer` 验证 Markdown、公式和代码高亮展示。

- 日期：2026-07-04
- 应用：`frontend/apps/admin`
- 开发端口：`8002`
- 后端接口：沿用 `/api/admin/question/**`

## 已落地内容

新增管理端题库 API：

- `getAdminQuestionPage`
- `getAdminQuestion`
- `saveAdminQuestion`
- `deleteAdminQuestion`

新增页面与组件：

- `frontend/apps/admin/src/views/question/QuestionListView.vue`
- `frontend/apps/admin/src/views/question/QuestionEditView.vue`
- `frontend/apps/admin/src/components/UeditorField.vue`

新增静态资源：

- `frontend/apps/admin/public/admin/components/ueditor`

更新管理端路由和菜单：

- `/exam/question/list`
- `/exam/question/edit?id=:id`

## 关键修复

### Vue 3 dev 白屏问题

最初的 UEditor wrapper 在 Vue 模板中直接写：

```html
<script type="text/plain"></script>
```

生产构建能通过，但 Vite dev 在进入编辑页时会报错：

```text
Tags with side effect (<script> and <style>) are ignored in client component templates.
```

这会导致动态路由模块加载失败，表现为进入题目编辑页后页面白屏。已改为在 `onMounted` 中运行时创建 `script[type=text/plain]` 宿主节点，并把 `data-editor-id` 暴露到 `.ueditor-field`，供验证脚本稳定定位 UEditor 实例。

### 第三方类型声明

`@xzs/admin` 引入 `@xzs/question-renderer` 后，TypeScript 构建会因为 `markdown-it-texmath` 缺失声明失败。已在 `question-renderer` 的 `render.ts` 中显式引用本包声明文件，避免每个 app 重复声明。

## 严格验证

`pnpm --dir frontend verify:admin-ui` 已从基础截图验证扩展为题库闭环验证：

1. 登录管理端。
2. 验证 Dashboard API。
3. 验证学科列表 API。
4. 通过管理端 API 创建带唯一 marker 的临时单选题。
5. 进入题目列表，按知识点筛选临时题。
6. 打开题目预览，断言 Markdown、KaTeX 和代码高亮已渲染。
7. 进入题目编辑页，断言 UEditor 运行时、脚本资源和两个编辑器实例已加载。
8. 通过 UEditor 写入题干和解析，断言右侧预览同步渲染公式。
9. 点击保存，等待 `/api/admin/question/edit` 成功。
10. 重新读取 `/api/admin/question/select/{id}`，断言保存内容回读成功。
11. 再次打开预览，断言编辑后的公式可见。
12. 调用 `/api/admin/question/delete/{id}` 清理临时题。
13. 退出管理端。

截图输出目录：

```text
D:\workspace\xzs\.tmp\playwright\admin-ui
```

截图清单：

- `01-login.png`
- `02-dashboard.png`
- `03-subject-list.png`
- `04-question-list.png`
- `05-question-preview.png`
- `06-question-edit.png`
- `07-question-preview-after-save.png`
- `08-logout.png`

## 本次验证结果

题目渲染包单元测试：

```powershell
pnpm --dir frontend --filter @xzs/question-renderer test
```

结果：通过，`9 passed`。

管理端构建：

```powershell
pnpm --dir frontend --filter @xzs/admin build
```

结果：通过，Vite reported `built in 5.00s`。

管理端严格截图验证：

```powershell
$env:XZS_ADMIN_BASE_URL='http://localhost:8002'
$env:XZS_ADMIN_API_BASE_URL='http://localhost:8000'
pnpm --dir frontend verify:admin-ui
```

结果：通过。

## 已知剩余

- 当前题库编辑最小闭环覆盖单选题、题干、解析、选项文本、预览和保存；多选、判断、填空、简答需要继续扩展 UI 和测试样本。
- 当前保留 UEditor 运行时以确保历史内容兼容；最终架构文档中的新富文本替换仍未完成。
- 图片上传入口已关闭；UEditor 公式插件弹窗尚未做浏览器交互级验证。当前验证覆盖 `$...$` Markdown/KaTeX 渲染、历史图片外链展示和 UEditor 内容保存。
- 管理端 Vue 3 在阶段 7 完成时仍未接管后端 `/admin` static 生产入口；该事项已在阶段 8 切换完成。

## 阶段 7 结论

管理端题库的 Vue 3 最小可用闭环已经跑通，且补上了会导致 dev/HMR 白屏的 UEditor 宿主实现问题。下一阶段应进入管理端生产候选和 `/admin` 发布入口切换，并继续扩展题型覆盖和管理端剩余模块。
