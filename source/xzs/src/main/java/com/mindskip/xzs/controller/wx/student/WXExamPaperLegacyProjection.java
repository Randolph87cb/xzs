package com.mindskip.xzs.controller.wx.student;

import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperTitleItemVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;

import java.util.HashSet;
import java.util.Set;

/**
 * Adds the shared question-group title to the legacy flat question list used by
 * mini-program versions before 1dc23f66. The structured paperItems projection
 * remains unchanged for current clients.
 */
public final class WXExamPaperLegacyProjection {
    private static final String TITLE_SEPARATOR = "<br/>";

    private WXExamPaperLegacyProjection() { }

    public static ExamPaperEditRequestVM apply(ExamPaperEditRequestVM paper) {
        if (paper == null || paper.getTitleItems() == null) {
            return paper;
        }

        Set<Integer> projectedGroupIds = new HashSet<>();
        for (ExamPaperTitleItemVM titleItem : paper.getTitleItems()) {
            if (titleItem == null || titleItem.getQuestionItems() == null) {
                continue;
            }
            for (QuestionEditRequestVM question : titleItem.getQuestionItems()) {
                if (question == null || question.getQuestionGroupId() == null
                        || isBlank(question.getQuestionGroupTitle())
                        || !projectedGroupIds.add(question.getQuestionGroupId())) {
                    continue;
                }
                question.setTitle(combineTitles(question.getQuestionGroupTitle(), question.getTitle()));
            }
        }
        return paper;
    }

    private static String combineTitles(String groupTitle, String questionTitle) {
        if (isBlank(questionTitle)) {
            return groupTitle;
        }
        String prefix = groupTitle + TITLE_SEPARATOR;
        return questionTitle.startsWith(prefix) ? questionTitle : prefix + questionTitle;
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
