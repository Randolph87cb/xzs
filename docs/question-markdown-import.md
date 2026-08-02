# Markdown 题目导入格式

当前 Markdown 导入接口支持单选题，接口路径：

```text
POST /api/admin/question/import/markdown
Content-Type: multipart/form-data
```

该接口用于管理端手动导入普通单选题。GESP 历年客观题使用 `scripts/import-gesp-objective-questions.ps1` 批量导入，题型、试卷标题、顺序和按级别隔离的知识点规则见 `docs/question-bank/GESP/README.md`。

CSP 程序阅读/程序填空不走这个普通 Markdown 接口。它们由 `scripts/import-csp-objective-questions.ps1` 按 `raw/all.json` 中稳定的 `import_source + parentProblemNo + subQuestionNo` 建立题组，禁止通过题面相似度推断父子关系。

## 请求字段

- `file`：必填，UTF-8 编码的 Markdown 文件。
- `subjectId`：必填，题目所属学科 ID。题目年级会从学科自动带出。
- `score`：选填，每题分值，默认 `1`。
- `difficult`：选填，难度，范围 `1` 到 `5`，默认 `1`。
- `analyze`：选填，默认解析；题目内没有解析时使用，默认 `暂无解析`。

## 文件格式

每道题使用二级标题开始，格式为 `## 第N题`。题干写在标题后，选项使用大写字母加英文句点，答案使用 `答案：X`。

```markdown
## 第1题

这里是题干，可以包含多行文本、行内代码 `code`、加粗 **text**，也可以包含 fenced code block。

A. 选项 A
B. 选项 B
C. 选项 C
D. 选项 D

答案：B

解析：可选解析。如果不写，使用请求字段 analyze 的默认解析。
```

## 对齐到系统字段

- `## 第N题` 只用于拆题和错误定位，不保存到题干。
- 题干会保存到 `QuestionEditRequestVM.title`。
- 选项会保存到 `QuestionEditRequestVM.items`，其中 `A`、`B` 等对应 `prefix`，选项内容对应 `content`。
- `答案：X` 会保存到 `QuestionEditRequestVM.correct`。
- 解析保存到 `QuestionEditRequestVM.analyze`。
- `questionType` 固定为 `1`，即单选题。

## 示例

仓库中的 `.tmp/选择题.md` 符合该格式，可通过该接口导入。

## CSP 复合题契约

- `t_question_group.group_type` 表示内容结构：`1=程序阅读`、`2=程序填空`。
- `t_question.question_type` 仍只表示子题作答/判分类型；题组本身不生成答案记录。
- 子题通过 `question_group_id + group_item_order` 归组，原有子题 ID、答案、分值和历史答卷关系保持不变。
- 管理 API 为 `/api/admin/question/group/page|select/{id}|edit|delete/{id}`。编辑请求的 `questionItems` 是有序完整子题，子题用 `groupItemOrder` 表示组内顺序。
- 普通题分页默认 `questionGroupMode=INDEPENDENT`；可显式传 `GROUP_CHILD` 或 `ALL`。普通随机抽题始终排除组内子题。
- 新试卷 frame 的标题项使用 `paperItems`。`QUESTION` 条目保存题目 `id + itemOrder`；`QUESTION_GROUP` 保存题组 `id`，并在 `questionItems` 中快照子题 `id + groupItemOrder + itemOrder`。后端仍双读旧 `questionItems` frame，答案提交仍是扁平 `questionId + itemOrder`。
