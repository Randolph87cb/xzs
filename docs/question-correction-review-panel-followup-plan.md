# 改错审核右侧审核处理与 AI 内容修正方案

## 背景与现状

- 管理端改错审核页位于 `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`。
- 当前右侧栏由多个卡片组成：
  - `correction-workbench__review-card`：审核处理。
  - `correction-workbench__ai-card`：AI 预审建议。
  - 学生改错、审核历史。
- 当前样式中 `correction-workbench__review-card` 设置了 `position: sticky; top: 0; z-index: 2; box-shadow`，在右侧滚动栏里会表现得像一个浮窗，并遮挡后续 AI 内容或后面的操作区。
- 当前 AI 自动填入审核意见使用 `getStudentVisibleAiFeedback()`，逻辑为 `studentFeedback || reviewComment`。如果旧记录或模型返回里 `reviewComment` 是老师内部判断口吻，就会被填入“审核意见” textarea，导致学生看到不合适的内容。

## 结论

推荐把右侧“审核处理”和“AI 预审结构”合并成一个普通滚动面板，取消 sticky 浮层；面板内部按从上到下固定为：审核表单、AI 概览、AI 详细原因。审核意见 textarea 只能填入明确的学生可见字段 `studentFeedback`，不能再兜底使用可能是老师口吻的 `reviewComment`。

## 本次确认范围

- 单题 AI 按钮放入合并后的右侧面板中，位置放在 AI 概览标题右侧或概览区底部，文案继续使用“AI 预审当前题 / 重新预审当前题”。
- 页面顶部继续保留“AI 批量预审”按钮。
- AI prompt 保持当前 JSON 字段结构：`reviewResult`、`teacherReason`、`studentFeedback`、`missingPoints`、`confidence`。
- 本次实现重点是 UI 合并、按钮位置、学生可见草稿填充来源收紧；不新增数据库字段，不改变 AI 接口路径。

## 需求拆解

### 1. 取消右侧审核处理浮窗

- 当前现状：
  - `correction-workbench__review-card` 使用 sticky 定位和 z-index。
  - 右侧栏本身也有 `overflow: auto`，导致审核卡片在滚动时覆盖同一区域后面的内容。
- 判断：
  - 这不是浏览器弹窗，而是 sticky 卡片造成的层叠效果。保留 sticky 会继续影响点击和阅读。
- 修改方案：
  - 删除 `.correction-workbench__review-card` 的 `position: sticky`、`top`、`z-index` 和强阴影。
  - 不再把审核处理作为独立浮层卡片，而是合并到一个新的右侧面板，如 `correction-workbench__review-panel`。
  - 右侧面板只保留一个滚动上下文：`side-panel` 或 `review-panel` 二选一，不要内外都滚。
  - 面板底部按钮可以普通随内容滚动；如果需要固定按钮，使用面板内部 footer，不能覆盖 AI 内容区域。
- 影响范围：
  - `frontend/apps/admin/src/views/question/QuestionCorrectionReviewView.vue`
- 验证方案：
  - 进入 `/admin/index.html#/exam/question/correction` 后，右侧不出现覆盖式浮层。
  - 滚动右侧栏时，“审核处理”“AI 概览”“AI 详细原因”依次自然滚动，后面的内容都能点击。
  - Chrome 控制台无新增 error。

### 2. 右侧内容合并为一个清晰面板

- 当前现状：
  - 审核处理和 AI 预审建议是两个视觉卡片，老师需要在两个卡片之间跳转理解。
  - 截图中 AI 内容被下方和旁边滚动条割裂，阅读成本高。
- 判断：
  - 右侧的任务是完成一次审核，AI 信息应该服务审核表单，而不是另开一个“弹层感”的卡片。
- 修改方案：
  - 模板改成一个主面板，顺序为：
    1. **审核草稿**：审核结果 segmented control、审核意见 textarea、仅保存、保存并下一题、应用 AI 建议。
    2. **AI 概览**：建议结果、置信度、缺失点，使用紧凑信息格。
    3. **AI 详细原因**：给老师看的理由、返回给学生的建议、失败原因、完成时间。
  - “AI 预审当前题 / 重新预审当前题”放在 AI 概览标题右侧或概览区底部，不放到浮层外。
  - 学生改错和审核历史保留在同一右侧栏下方，但用折叠区或次级卡片，避免抢首屏。
- 影响范围：
  - `QuestionCorrectionReviewView.vue` template 和 scoped style。
- 验证方案：
  - 1440px 与 1920px 宽度下右侧面板不遮挡中间题目。
  - 老师首屏能看到审核意见 textarea、审核结果和保存按钮。
  - AI 置信度、缺失点、老师理由、学生建议都能在同一个面板内读到。

### 3. 审核意见只填学生可见内容

- 当前现状：
  - 前端自动填表函数为 `getStudentVisibleAiFeedback(aiReview)`。
  - 但当前实现仍兜底 `aiReview.reviewComment`。
  - 后端新结构中 `reviewComment` 被设计为兼容旧字段，新旧记录混合时它不一定可靠。
- 判断：
  - 用户看到的“预先填好内容不是写给学生看的部分”，核心风险来自兜底字段语义不稳和 AI 输出约束不够硬。
- 修改方案：
  - 前端自动填入 textarea 的来源改为：
    - 首选：`aiReview.studentFeedback`。
    - 不再把 `reviewComment`、`teacherReason`、`reason` 等字段兜底写入 textarea。
    - 旧字段 `reviewComment` 只在 AI 详细原因里标注为“旧字段兼容”展示，供老师参考。
  - `getStudentVisibleAiFeedback()` 改名或拆分为更明确的函数：
    - `getAiStudentFeedbackDraft()`：只返回可写入 textarea 的学生反馈。
    - `getAiTeacherReason()`：只用于 AI 详细原因展示。
  - 当没有学生可见建议时：
    - textarea 不自动填内容。
    - 显示提示：“AI 未返回学生可见建议，请老师手动填写或重新预审。”
  - “应用 AI 建议”按钮只应用学生可见建议，不应用老师理由。
- 影响范围：
  - `QuestionCorrectionReviewView.vue` 的 `applyAiSuggestion()`、`canApplyAiSuggestion`、AI 展示区。
- 验证方案：
  - 构造 AI 记录：只有 `teacherReason`，无 `studentFeedback`，textarea 不自动填。
  - 构造 AI 记录：`studentFeedback` 和 `teacherReason` 同时存在，textarea 只填 `studentFeedback`。
  - 旧记录仅有 `reviewComment` 时仍可显示，但需在 UI 上标注“旧字段兼容”，避免误认为新结构。

### 4. 后端 AI 输出约束（本次不改）

- 当前现状：
  - 后端 prompt 已要求 `studentFeedback` 面向学生，但仍允许模型在内容里出现“建议返回”“学生已经”等老师口吻。
  - `parseSuggestion()` 里 `studentFeedback` 缺失时会使用 `reviewComment/suggestion` 兜底。
- 判断：
  - 仅靠前端防守不够，模型输出也要更明确地约束语气和字段职责。
- 本次确认：
  - 用户已确认 prompt 继续使用当前 JSON 字段结构：`reviewResult`、`teacherReason`、`studentFeedback`、`missingPoints`、`confidence`。
  - 本次不修改后端 prompt、AI 接口路径、数据库结构或解析兼容策略。
- 后续可选方案：
  - 如果后续仍出现 `studentFeedback` 里混入老师口吻，再单独调整 `QuestionCorrectionAiReviewService.buildMessages()` 的字段说明和语气约束。
  - 如果旧模型字段长期存在，再单独评估历史记录清洗或重跑 AI 预审。
- 后续影响范围：
  - `source/xzs/src/main/java/com/mindskip/xzs/service/QuestionCorrectionAiReviewService.java`
- 后续验证方案：
  - 单元级或最小方法测试：模拟 JSON 缺失 `studentFeedback` 时不会生成老师理由作为学生反馈。
  - 手动 AI 预审一题，确认 textarea 内容是直接给学生看的修改建议。

## 推荐执行顺序

1. 前端先取消 sticky 浮层并合并右侧面板，解决“挡住点不到”的即时问题。
2. 前端收紧自动填入逻辑，只允许 `studentFeedback` 自动进入 textarea。
3. 保持后端 prompt JSON 结构不变，前端只把 `studentFeedback` 当作学生可见草稿。
4. 浏览器验证管理端真实页面，并用至少两条 AI 记录覆盖“新结构”和“旧兼容”。

## 风险与待确认

- 已有历史 AI 记录里的 `reviewComment` 可能已经是老师口吻；不能简单批量当作学生反馈展示，需要保守处理。
- 如果用户希望旧记录也自动转成学生口吻，需要额外做一次 AI 重新预审或人工清洗，不建议在本次 UI 修复里自动改历史数据。
- 右侧按钮如果做固定底部，需要确保不覆盖 textarea 或 AI 详情；优先采用普通文档流。
