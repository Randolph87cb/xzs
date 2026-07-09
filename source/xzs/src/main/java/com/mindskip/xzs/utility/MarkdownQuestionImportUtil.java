package com.mindskip.xzs.utility;

import com.mindskip.xzs.viewmodel.admin.question.QuestionEditItemVM;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class MarkdownQuestionImportUtil {

    private static final Pattern QUESTION_HEADING = Pattern.compile("^##\\s*第\\s*(\\d+)\\s*题\\s*$");
    private static final Pattern OPTION_LINE = Pattern.compile("^([A-Z])\\.\\s*(.*)$");
    private static final Pattern ANSWER_LINE = Pattern.compile("^答案\\s*[:：]\\s*([A-Z])\\s*$");
    private static final Pattern ANALYZE_LINE = Pattern.compile("^解析\\s*[:：]\\s*(.*)$");

    private MarkdownQuestionImportUtil() {
    }

    public static List<MarkdownQuestion> parseSingleChoice(String markdown, String defaultAnalyze) {
        if (markdown == null || markdown.trim().isEmpty()) {
            throw new IllegalArgumentException("Markdown 内容不能为空");
        }

        List<QuestionBlock> blocks = splitQuestionBlocks(markdown);
        if (blocks.isEmpty()) {
            throw new IllegalArgumentException("未找到题目标题，请使用“## 第1题”格式");
        }

        List<MarkdownQuestion> questions = new ArrayList<>();
        for (QuestionBlock block : blocks) {
            questions.add(parseQuestionBlock(block, defaultAnalyze));
        }
        return questions;
    }

    private static List<QuestionBlock> splitQuestionBlocks(String markdown) {
        String normalized = markdown.replace("\uFEFF", "").replace("\r\n", "\n").replace("\r", "\n");
        String[] lines = normalized.split("\n", -1);
        List<QuestionBlock> blocks = new ArrayList<>();
        QuestionBlock current = null;

        for (String line : lines) {
            Matcher headingMatcher = QUESTION_HEADING.matcher(line.trim());
            if (headingMatcher.matches()) {
                if (current != null) {
                    blocks.add(current);
                }
                current = new QuestionBlock(Integer.parseInt(headingMatcher.group(1)));
                continue;
            }

            if (current != null) {
                current.lines.add(line);
            }
        }

        if (current != null) {
            blocks.add(current);
        }
        return blocks;
    }

    private static MarkdownQuestion parseQuestionBlock(QuestionBlock block, String defaultAnalyze) {
        List<String> titleLines = new ArrayList<>();
        List<QuestionEditItemVM> items = new ArrayList<>();
        List<String> analyzeLines = new ArrayList<>();
        String correct = null;
        QuestionEditItemVM currentItem = null;
        boolean inFence = false;
        boolean inMathBlock = false;
        boolean answerSeen = false;

        for (String rawLine : block.lines) {
            String line = rawLine.trim();
            if (line.startsWith("```")) {
                inFence = !inFence;
            }
            if (!inFence && isMathBlockDelimiter(line)) {
                inMathBlock = !inMathBlock;
            }

            boolean canParseStructure = !inFence && !inMathBlock;
            if (canParseStructure && !answerSeen) {
                Matcher answerMatcher = ANSWER_LINE.matcher(line);
                if (answerMatcher.matches()) {
                    correct = answerMatcher.group(1);
                    answerSeen = true;
                    currentItem = null;
                    continue;
                }

                Matcher optionMatcher = OPTION_LINE.matcher(rawLine);
                if (optionMatcher.matches()) {
                    currentItem = new QuestionEditItemVM();
                    currentItem.setPrefix(optionMatcher.group(1));
                    currentItem.setContent(optionMatcher.group(2));
                    items.add(currentItem);
                    continue;
                }
            }

            if (answerSeen) {
                Matcher analyzeMatcher = ANALYZE_LINE.matcher(line);
                if (canParseStructure && analyzeMatcher.matches()) {
                    analyzeLines.add(analyzeMatcher.group(1));
                } else {
                    analyzeLines.add(rawLine);
                }
            } else if (currentItem == null) {
                titleLines.add(rawLine);
            } else {
                String existing = currentItem.getContent();
                currentItem.setContent(existing + "\n" + rawLine);
            }
        }

        String titleMarkdown = trimBlankLines(titleLines);
        if (titleMarkdown.isEmpty()) {
            throw new IllegalArgumentException("第" + block.order + "题缺少题干");
        }
        if (items.size() < 2) {
            throw new IllegalArgumentException("第" + block.order + "题至少需要两个选项");
        }
        if (correct == null) {
            throw new IllegalArgumentException("第" + block.order + "题缺少答案行");
        }
        if (!containsPrefix(items, correct)) {
            throw new IllegalArgumentException("第" + block.order + "题答案不在选项中: " + correct);
        }
        assertUniquePrefixes(items, block.order);

        String analyzeMarkdown = trimBlankLines(analyzeLines);
        if (analyzeMarkdown.isEmpty()) {
            analyzeMarkdown = defaultAnalyze(defaultAnalyze);
        }

        return new MarkdownQuestion(block.order, titleMarkdown, items, correct, analyzeMarkdown);
    }

    private static boolean isMathBlockDelimiter(String line) {
        return "$$".equals(line) || "\\[".equals(line) || "\\]".equals(line);
    }

    private static String defaultAnalyze(String defaultAnalyze) {
        if (defaultAnalyze == null || defaultAnalyze.trim().isEmpty()) {
            return "暂无解析";
        }
        return defaultAnalyze.trim();
    }

    private static boolean containsPrefix(List<QuestionEditItemVM> items, String prefix) {
        for (QuestionEditItemVM item : items) {
            if (prefix.equals(item.getPrefix())) {
                return true;
            }
        }
        return false;
    }

    private static void assertUniquePrefixes(List<QuestionEditItemVM> items, int order) {
        Set<String> seenPrefixes = new HashSet<>();
        for (QuestionEditItemVM item : items) {
            if (!seenPrefixes.add(item.getPrefix())) {
                throw new IllegalArgumentException("第" + order + "题存在重复选项: " + item.getPrefix());
            }
        }
    }

    private static String trimBlankLines(List<String> lines) {
        int start = 0;
        int end = lines.size();
        while (start < end && lines.get(start).trim().isEmpty()) {
            start++;
        }
        while (end > start && lines.get(end - 1).trim().isEmpty()) {
            end--;
        }
        StringBuilder builder = new StringBuilder();
        for (int i = start; i < end; i++) {
            if (builder.length() > 0) {
                builder.append('\n');
            }
            builder.append(lines.get(i));
        }
        return builder.toString().trim();
    }

    private static class QuestionBlock {
        private final int order;
        private final List<String> lines = new ArrayList<>();

        private QuestionBlock(int order) {
            this.order = order;
        }
    }

    public static class MarkdownQuestion {
        private final int order;
        private final String title;
        private final List<QuestionEditItemVM> items;
        private final String correct;
        private final String analyze;

        private MarkdownQuestion(int order, String title, List<QuestionEditItemVM> items, String correct, String analyze) {
            this.order = order;
            this.title = title;
            this.items = items;
            this.correct = correct;
            this.analyze = analyze;
        }

        public int getOrder() {
            return order;
        }

        public String getTitle() {
            return title;
        }

        public List<QuestionEditItemVM> getItems() {
            return items;
        }

        public String getCorrect() {
            return correct;
        }

        public String getAnalyze() {
            return analyze;
        }
    }
}
