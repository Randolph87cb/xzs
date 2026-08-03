package com.mindskip.xzs.controller.wx.student;

import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperItemVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperTitleItemVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import org.junit.Test;

import java.util.Arrays;

import static org.junit.Assert.assertEquals;

public class WXExamPaperLegacyProjectionTest {

    @Test
    public void projectsSharedTitleOnlyOntoFirstFlatChildAndLeavesStructuredItemsUntouched() {
        ExamPaperEditRequestVM paper = paper();

        WXExamPaperLegacyProjection.apply(paper);

        ExamPaperTitleItemVM title = paper.getTitleItems().get(0);
        assertEquals("独立题题干", title.getQuestionItems().get(0).getTitle());
        assertEquals("共享题面<br/>题组子题一", title.getQuestionItems().get(1).getTitle());
        assertEquals("题组子题二", title.getQuestionItems().get(2).getTitle());

        ExamPaperItemVM group = title.getPaperItems().get(1);
        assertEquals("共享题面", group.getTitle());
        assertEquals("题组子题一", group.getQuestionItems().get(0).getTitle());
        assertEquals("题组子题二", group.getQuestionItems().get(1).getTitle());
    }

    static ExamPaperEditRequestVM paper() {
        QuestionEditRequestVM independentFlat = question(1, "独立题题干", null, null);
        QuestionEditRequestVM firstFlat = question(2, "题组子题一", 9, "共享题面");
        QuestionEditRequestVM secondFlat = question(3, "题组子题二", 9, "共享题面");

        ExamPaperItemVM independentItem = new ExamPaperItemVM();
        independentItem.setType("QUESTION");
        independentItem.setId(1);
        independentItem.setQuestionItems(Arrays.asList(question(1, "独立题题干", null, null)));

        ExamPaperItemVM groupItem = new ExamPaperItemVM();
        groupItem.setType("QUESTION_GROUP");
        groupItem.setId(9);
        groupItem.setTitle("共享题面");
        groupItem.setQuestionItems(Arrays.asList(
                question(2, "题组子题一", 9, "共享题面"),
                question(3, "题组子题二", 9, "共享题面")));

        ExamPaperTitleItemVM title = new ExamPaperTitleItemVM();
        title.setName("客观题");
        title.setQuestionItems(Arrays.asList(independentFlat, firstFlat, secondFlat));
        title.setPaperItems(Arrays.asList(independentItem, groupItem));

        ExamPaperEditRequestVM paper = new ExamPaperEditRequestVM();
        paper.setId(101);
        paper.setTitleItems(Arrays.asList(title));
        return paper;
    }

    private static QuestionEditRequestVM question(Integer id, String title, Integer groupId, String groupTitle) {
        QuestionEditRequestVM question = new QuestionEditRequestVM();
        question.setId(id);
        question.setTitle(title);
        question.setQuestionGroupId(groupId);
        question.setQuestionGroupTitle(groupTitle);
        return question;
    }
}
