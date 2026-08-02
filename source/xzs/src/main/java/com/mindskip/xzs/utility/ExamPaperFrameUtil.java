package com.mindskip.xzs.utility;

import com.mindskip.xzs.domain.exam.ExamPaperItemObject;
import com.mindskip.xzs.domain.exam.ExamPaperQuestionItemObject;
import com.mindskip.xzs.domain.exam.ExamPaperTitleItemObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class ExamPaperFrameUtil {
    private ExamPaperFrameUtil() { }

    public static List<ExamPaperQuestionItemObject> expandQuestionItems(ExamPaperTitleItemObject title) {
        if (title.getPaperItems() == null || title.getPaperItems().isEmpty()) {
            return title.getQuestionItems() == null ? Collections.emptyList() : title.getQuestionItems();
        }
        List<ExamPaperQuestionItemObject> expanded = new ArrayList<>();
        for (ExamPaperItemObject paperItem : title.getPaperItems()) {
            if (ExamPaperItemObject.QUESTION_GROUP.equals(paperItem.getType())) {
                if (paperItem.getQuestionItems() != null) {
                    expanded.addAll(paperItem.getQuestionItems());
                }
            } else {
                ExamPaperQuestionItemObject question = new ExamPaperQuestionItemObject();
                question.setId(paperItem.getId());
                question.setItemOrder(paperItem.getItemOrder());
                expanded.add(question);
            }
        }
        return expanded;
    }

    public static List<ExamPaperQuestionItemObject> expandQuestionItems(List<ExamPaperTitleItemObject> titles) {
        List<ExamPaperQuestionItemObject> expanded = new ArrayList<>();
        if (titles == null) { return expanded; }
        for (ExamPaperTitleItemObject title : titles) {
            expanded.addAll(expandQuestionItems(title));
        }
        return expanded;
    }
}
