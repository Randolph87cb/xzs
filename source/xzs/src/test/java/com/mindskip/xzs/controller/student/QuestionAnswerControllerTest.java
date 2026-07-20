package com.mindskip.xzs.controller.student;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.domain.ExamPaperQuestionCustomerAnswer;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.ExamPaperQuestionCustomerAnswerService;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.viewmodel.student.question.answer.QuestionPageStudentRequestVM;
import com.mindskip.xzs.viewmodel.student.question.answer.QuestionPageStudentResponseVM;
import com.mindskip.xzs.viewmodel.student.question.answer.QuestionWrongHistoryVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Date;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class QuestionAnswerControllerTest {

    private ExamPaperQuestionCustomerAnswerService answerService;
    private QuestionService questionService;
    private TextContentService textContentService;
    private QuestionAnswerController controller;

    @Before
    public void setUp() {
        answerService = mock(ExamPaperQuestionCustomerAnswerService.class);
        questionService = mock(QuestionService.class);
        textContentService = mock(TextContentService.class);
        controller = new QuestionAnswerController(
                answerService,
                questionService,
                textContentService,
                mock(SubjectService.class),
                mock(JdbcTemplate.class));

        WebContext webContext = mock(WebContext.class);
        when(webContext.getCurrentUser()).thenReturn(user());
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void wrongQuestionPageReturnsAggregatedRowsWithShortTitle() {
        QuestionPageStudentResponseVM row = new QuestionPageStudentResponseVM();
        row.setId(13);
        row.setQuestionId(101);
        row.setLatestCustomerAnswerId(13);
        row.setKnowledgePoint("数组");
        row.setWrongCount(3);
        when(answerService.studentWrongQuestionPage(any())).thenReturn(new PageInfo<>(Arrays.asList(row)));

        Question question = new Question();
        question.setId(101);
        question.setInfoTextContentId(201);
        when(questionService.selectById(101)).thenReturn(question);
        when(textContentService.selectById(201)).thenReturn(new TextContent("{\"titleContent\":\"<p>题干 **A**</p>\"}", new Date()));

        QuestionPageStudentRequestVM request = new QuestionPageStudentRequestVM();
        request.setPageIndex(1);
        request.setPageSize(10);
        RestResponse<PageInfo<QuestionPageStudentResponseVM>> response = controller.wrongQuestionPage(request);

        assertEquals(1, response.getCode());
        QuestionPageStudentResponseVM actual = response.getResponse().getList().get(0);
        assertEquals(Integer.valueOf(13), actual.getId());
        assertEquals(Integer.valueOf(101), actual.getQuestionId());
        assertEquals(Integer.valueOf(3), actual.getWrongCount());
        assertEquals("题干 **A**", actual.getShortTitle());
    }

    @Test
    public void wrongQuestionHistoryFormatsScoreAndTime() {
        QuestionWrongHistoryVM row = new QuestionWrongHistoryVM();
        row.setCustomerAnswerId(13);
        row.setRawUserScore(85);
        row.setCreateTime(new Date(0));
        when(answerService.studentWrongQuestionHistory(7, 101)).thenReturn(Arrays.asList(row));

        RestResponse<List<QuestionWrongHistoryVM>> response = controller.wrongQuestionHistory(101);

        assertEquals(1, response.getCode());
        assertEquals("8.5", response.getResponse().get(0).getUserScore());
        assertEquals(DateTimeUtil.dateFormat(new Date(0)), response.getResponse().get(0).getCreateTimeText());
    }

    @Test
    public void selectRejectsMissingCustomerAnswer() {
        when(answerService.selectById(13)).thenReturn(null);

        RestResponse response = controller.select(13);

        assertEquals(2, response.getCode());
        verify(answerService, never()).examPaperQuestionCustomerAnswerToVM(any());
        verify(questionService, never()).getQuestionEditRequestVM(anyInt());
    }

    @Test
    public void selectRejectsOtherUsersCustomerAnswer() {
        ExamPaperQuestionCustomerAnswer answer = new ExamPaperQuestionCustomerAnswer();
        answer.setId(13);
        answer.setCreateUser(8);
        answer.setQuestionId(101);
        when(answerService.selectById(13)).thenReturn(answer);

        RestResponse response = controller.select(13);

        assertEquals(2, response.getCode());
        verify(answerService, never()).examPaperQuestionCustomerAnswerToVM(any());
        verify(questionService, never()).getQuestionEditRequestVM(anyInt());
    }

    private User user() {
        User user = new User();
        user.setId(7);
        return user;
    }
}
