package com.mindskip.xzs.utility;

import com.mindskip.xzs.viewmodel.admin.question.QuestionEditItemVM;
import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;

public class MarkdownQuestionImportUtilTest {

    @Test
    public void parseSingleChoiceKeepsMarkdownSource() {
        String markdown = "## 第1题\n"
                + "阅读 **题干** 和 `code`：\n"
                + "```java\n"
                + "String text = \"A. not option\";\n"
                + "```\n"
                + "$$\n"
                + "x < y\n"
                + "答案：A\n"
                + "$$\n"
                + "A. 选项 **A** 包含 `inline`\n"
                + "继续 <保留>\n"
                + "B. 选项 B\n"
                + "答案：A\n"
                + "解析：使用 $x < y$ 和 **Markdown**\n"
                + "```text\n"
                + "解析：不要剥离\n"
                + "```\n";

        List<MarkdownQuestionImportUtil.MarkdownQuestion> questions =
                MarkdownQuestionImportUtil.parseSingleChoice(markdown, null);

        MarkdownQuestionImportUtil.MarkdownQuestion question = questions.get(0);
        assertEquals("阅读 **题干** 和 `code`：\n"
                + "```java\n"
                + "String text = \"A. not option\";\n"
                + "```\n"
                + "$$\n"
                + "x < y\n"
                + "答案：A\n"
                + "$$", question.getTitle());

        QuestionEditItemVM firstItem = question.getItems().get(0);
        assertEquals("A", firstItem.getPrefix());
        assertEquals("选项 **A** 包含 `inline`\n继续 <保留>", firstItem.getContent());
        assertEquals("B", question.getItems().get(1).getPrefix());
        assertEquals("A", question.getCorrect());
        assertEquals("使用 $x < y$ 和 **Markdown**\n"
                + "```text\n"
                + "解析：不要剥离\n"
                + "```", question.getAnalyze());
    }

    @Test
    public void parseSingleChoiceUsesPlainDefaultAnalyzeWhenBlank() {
        String markdown = "## 第1题\n"
                + "题干\n"
                + "A. 选项 A\n"
                + "B. 选项 B\n"
                + "答案：B\n";

        List<MarkdownQuestionImportUtil.MarkdownQuestion> questions =
                MarkdownQuestionImportUtil.parseSingleChoice(markdown, " ");

        assertEquals("暂无解析", questions.get(0).getAnalyze());
    }
}
