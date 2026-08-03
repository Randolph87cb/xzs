package com.mindskip.xzs.controller.wx.student;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.ExamPaperAnswer;
import com.mindskip.xzs.service.ExamPaperAnswerService;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperReadVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperSubmitVM;
import org.junit.Test;
import org.springframework.context.ApplicationEventPublisher;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class ExamPaperAnswerControllerTest {

    @Test
    public void readAppliesTheSameLegacyQuestionTitleProjection() {
        ExamPaperAnswerService answerService = mock(ExamPaperAnswerService.class);
        ExamPaperService paperService = mock(ExamPaperService.class);
        ExamPaperAnswer answer = new ExamPaperAnswer();
        answer.setId(12);
        answer.setExamPaperId(101);
        when(answerService.selectById(12)).thenReturn(answer);
        when(answerService.examPaperAnswerToVM(12)).thenReturn(new ExamPaperSubmitVM());
        when(paperService.examPaperToVM(101)).thenReturn(WXExamPaperLegacyProjectionTest.paper());
        ExamPaperAnswerController controller = new ExamPaperAnswerController(
                answerService,
                mock(SubjectService.class),
                mock(ApplicationEventPublisher.class),
                paperService);

        RestResponse<ExamPaperReadVM> response = controller.read(12);

        assertEquals("共享题面<br/>题组子题一",
                response.getResponse().getPaper().getTitleItems().get(0).getQuestionItems().get(1).getTitle());
        assertEquals("题组子题一",
                response.getResponse().getPaper().getTitleItems().get(0).getPaperItems().get(1)
                        .getQuestionItems().get(0).getTitle());
    }
}
