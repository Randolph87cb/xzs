package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import org.junit.Before;
import org.junit.Test;

import java.util.Collections;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class QuestionControllerTest {
    private QuestionService questionService;
    private QuestionController controller;

    @Before
    public void setUp() {
        questionService = mock(QuestionService.class);
        controller = new QuestionController(questionService, mock(TextContentService.class), mock(SubjectService.class));
    }

    @Test
    public void editReturnsExplicitFailureWhenGroupedChildDirectUpdateIsRejected() {
        QuestionEditRequestVM model = model();
        when(questionService.updateFullQuestion(model))
                .thenThrow(new IllegalArgumentException("题组子题请在题组中编辑"));

        RestResponse response = controller.edit(model);

        assertEquals(2, response.getCode());
        assertEquals("题组子题请在题组中编辑", response.getMessage());
        verify(questionService).updateFullQuestion(model);
    }

    private QuestionEditRequestVM model() {
        QuestionEditRequestVM model = new QuestionEditRequestVM();
        model.setId(100);
        model.setQuestionType(1);
        model.setSubjectId(10);
        model.setCorrect("A");
        model.setScore("5");
        model.setDifficult(1);
        model.setKnowledgePoint("综合");
        model.setTitle("题干");
        model.setAnalyze("解析");
        model.setItems(Collections.emptyList());
        return model;
    }
}
