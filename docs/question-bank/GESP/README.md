# GESP 客观题

本目录保存 GESP 真题题库中的客观题 Markdown 文件。

- 来源：`D:\workspace\教研中心\主线程\真题题库\GESP`
- 范围：各年份、各 C++ 级别目录下的 `判断题.md` 和 `选择题.md`
- 结构：保留来源目录中的年份和级别层级

## 导入规则

GESP 客观题使用 `scripts/import-gesp-objective-questions.ps1` 批量导入，不走管理端通用 Markdown 单选题上传接口。

- 目录格式必须是 `YYYY-MM/C++-N/选择题.md` 或 `YYYY-MM/C++-N/判断题.md`，其中 `N` 对应 GESP 级别和系统内的学科 ID。
- 每套真题导入为一张试卷，标题格式为 `YY年M月GESPN级客观题`。
- 题目顺序保持原卷顺序：前 15 道为选择题，后 10 道为判断题；缺失占位文件会跳过。
- Markdown 中的 `【知识点：...】` 作为原始知识点来源；导入到系统后会自动加上级别前缀，保存为 `GESP{N}级/{知识点}`，例如 `GESP1级/输入输出`、`GESP2级/输入输出`。
- 题干、解析和选择题选项默认按 Markdown 原文写入 `t_text_content`；判断题选项写入纯文本 `正确`、`错误`。如源题中出现 HTML 标签，只作为 Markdown 兼容语法保留，不再额外转换为 HTML。
- 导入脚本默认按 `import_batch + import_source + import_question_order` 或 `question_code` 原地更新已有题目，不再先删题再重插，避免改变已有 `question_id`。只有显式传入 `-CleanLegacyJsonDuplicates` 时，才会清理可确认已有新元数据题目对应的旧 JSON 重复题。
- 不同级别的同名知识点必须视为不同知识点，避免智能训练、随机训练和后台筛选把不同级别题目混在一起。

## 维护与验证

- 本地预检：运行 `.\scripts\import-gesp-objective-questions.ps1 -DryRun`，输出中的 `Knowledge points` 应全部带有 `GESP{N}级/` 前缀。
- 远端 Markdown 内容迁移 SQL：运行 `.\scripts\import-gesp-objective-questions.ps1 -MigrationSqlOnly`，脚本只生成 `.tmp/runtime/migrate-gesp-markdown-content.sql`，不会直接执行远端写入；SQL 内包含匹配、待更新和旧 JSON 重复候选统计。
- 远端已有 GESP 题目如需修复知识点命名，可在管理员登录后调用 `POST /api/admin/question/normalizeGespKnowledgePoints`。
- 修复后抽查 `POST /api/admin/smartTraining/knowledgePoints/{subjectId}`，返回项应全部以对应的 `GESP{subjectId}级/` 开头。
