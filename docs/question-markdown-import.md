# Markdown 题目导入格式

当前 Markdown 导入接口支持单选题，接口路径：

```text
POST /api/admin/question/import/markdown
Content-Type: multipart/form-data
```

该接口用于管理端手动导入普通单选题。GESP 历年客观题使用 `scripts/import-gesp-objective-questions.ps1` 批量导入，题型、试卷标题、顺序和按级别隔离的知识点规则见 `docs/question-bank/GESP/README.md`。

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
