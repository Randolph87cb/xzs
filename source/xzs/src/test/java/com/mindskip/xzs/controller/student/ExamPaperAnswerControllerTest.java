package com.mindskip.xzs.controller.student;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.domain.ExamPaperAnswer;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.ExamPaperAnswerService;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperSubmitVM;
import com.mindskip.xzs.viewmodel.student.exampaper.ExamPaperAnswerHistoryVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class ExamPaperAnswerControllerTest {

    private ExamPaperAnswerService examPaperAnswerService;
    private ExamPaperService examPaperService;
    private ExamPaperAnswerController controller;

    @Before
    public void setUp() {
        examPaperAnswerService = mock(ExamPaperAnswerService.class);
        examPaperService = mock(ExamPaperService.class);
        controller = new ExamPaperAnswerController(
                examPaperAnswerService,
                examPaperService,
                mock(SubjectService.class),
                mock(ApplicationEventPublisher.class));

        WebContext webContext = mock(WebContext.class);
        when(webContext.getCurrentUser()).thenReturn(user());
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void paperHistorySummarizesCurrentStudentAttempts() {
        when(examPaperAnswerService.selectPaperHistory(101, 7)).thenReturn(Arrays.asList(
                answer(3, 101, 90, 30, 8),
                answer(2, 101, 70, 40, null),
                answer(1, 101, 80, 50, 6)));

        RestResponse<ExamPaperAnswerHistoryVM> response = controller.paperHistory(101);

        assertEquals(1, response.getCode());
        ExamPaperAnswerHistoryVM history = response.getResponse();
        assertEquals(Integer.valueOf(101), history.getExamPaperId());
        assertEquals(Integer.valueOf(3), history.getAttemptCount());
        assertEquals("9", history.getBestScore());
        assertEquals("9", history.getLatestScore());
        assertEquals("8", history.getAverageScore());
        assertEquals(Integer.valueOf(8), history.getItems().get(0).getTaskExamId());
        assertEquals("3 秒", history.getItems().get(0).getDoTime());
    }

    @Test
    public void readRejectsMissingAnswer() {
        when(examPaperAnswerService.selectById(13)).thenReturn(null);

        RestResponse response = controller.read(13);

        assertEquals(2, response.getCode());
        verify(examPaperService, never()).examPaperToVM(org.mockito.ArgumentMatchers.any());
        verify(examPaperAnswerService, never()).examPaperAnswerToVM(org.mockito.ArgumentMatchers.any());
    }

    @Test
    public void readRejectsOtherUsersAnswer() {
        ExamPaperAnswer answer = answer(13, 101, 90, 30, null);
        answer.setCreateUser(8);
        when(examPaperAnswerService.selectById(13)).thenReturn(answer);

        RestResponse response = controller.read(13);

        assertEquals(2, response.getCode());
        verify(examPaperService, never()).examPaperToVM(org.mockito.ArgumentMatchers.any());
        verify(examPaperAnswerService, never()).examPaperAnswerToVM(org.mockito.ArgumentMatchers.any());
    }

    @Test
    public void editRejectsMissingAnswerBeforeJudge() {
        when(examPaperAnswerService.selectById(13)).thenReturn(null);

        RestResponse response = controller.edit(submit(13));

        assertEquals(2, response.getCode());
        verify(examPaperAnswerService, never()).judge(org.mockito.ArgumentMatchers.any());
    }

    @Test
    public void editRejectsOtherUsersAnswerBeforeJudge() {
        ExamPaperAnswer answer = answer(13, 101, 90, 30, null);
        answer.setCreateUser(8);
        when(examPaperAnswerService.selectById(13)).thenReturn(answer);

        RestResponse response = controller.edit(submit(13));

        assertEquals(2, response.getCode());
        verify(examPaperAnswerService, never()).judge(org.mockito.ArgumentMatchers.any());
    }

    private ExamPaperAnswer answer(Integer id, Integer paperId, Integer score, Integer paperScore, Integer taskExamId) {
        ExamPaperAnswer answer = new ExamPaperAnswer();
        answer.setId(id);
        answer.setExamPaperId(paperId);
        answer.setPaperName("paper");
        answer.setUserScore(score);
        answer.setSystemScore(score);
        answer.setPaperScore(paperScore);
        answer.setQuestionCorrect(1);
        answer.setQuestionCount(2);
        answer.setDoTime(id);
        answer.setStatus(2);
        answer.setTaskExamId(taskExamId);
        answer.setCreateUser(7);
        answer.setCreateTime(new Date(0));
        return answer;
    }

    private ExamPaperSubmitVM submit(Integer id) {
        ExamPaperSubmitVM submit = new ExamPaperSubmitVM();
        submit.setId(id);
        submit.setAnswerItems(Collections.emptyList());
        return submit;
    }

    private User user() {
        User user = new User();
        user.setId(7);
        return user;
    }
}
