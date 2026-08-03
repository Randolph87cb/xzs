package com.mindskip.xzs.controller.wx.student;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperEditRequestVM;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class ExamPaperControllerTest {

    @Test
    public void selectAppliesLegacyQuestionTitleProjection() {
        ExamPaperService examPaperService = mock(ExamPaperService.class);
        when(examPaperService.examPaperToVM(101)).thenReturn(WXExamPaperLegacyProjectionTest.paper());
        ExamPaperController controller = new ExamPaperController(examPaperService, mock(SubjectService.class));

        RestResponse<ExamPaperEditRequestVM> response = controller.select(101);

        assertEquals("共享题面<br/>题组子题一",
                response.getResponse().getTitleItems().get(0).getQuestionItems().get(1).getTitle());
        assertEquals("共享题面",
                response.getResponse().getTitleItems().get(0).getPaperItems().get(1).getTitle());
    }
}
