package com.mindskip.xzs.controller.student;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.controller.support.RecordingJdbcTemplate;
import com.mindskip.xzs.domain.ExamPaperQuestionCustomerAnswer;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.other.WrongQuestionWorkspaceData;
import com.mindskip.xzs.service.ExamPaperQuestionCustomerAnswerService;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.viewmodel.student.question.answer.QuestionPageStudentRequestVM;
import com.mindskip.xzs.viewmodel.student.question.answer.QuestionPageStudentResponseVM;
import com.mindskip.xzs.viewmodel.student.question.answer.QuestionTitleContentVM;
import com.mindskip.xzs.viewmodel.student.question.answer.QuestionWrongHistoryVM;
import com.mindskip.xzs.viewmodel.student.question.answer.WrongQuestionWorkspaceVM;
import com.mindskip.xzs.viewmodel.student.question.correction.QuestionCorrectionRecordVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperSubmitItemVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class QuestionAnswerControllerTest {

    private ExamPaperQuestionCustomerAnswerService answerService;
    private QuestionService questionService;
    private TextContentService textContentService;
    private RecordingJdbcTemplate jdbcTemplate;
    private QuestionAnswerController controller;

    @Before
    public void setUp() {
        answerService = mock(ExamPaperQuestionCustomerAnswerService.class);
        questionService = mock(QuestionService.class);
        textContentService = mock(TextContentService.class);
        jdbcTemplate = new RecordingJdbcTemplate();
        controller = new QuestionAnswerController(
                answerService,
                questionService,
                textContentService,
                mock(SubjectService.class),
                jdbcTemplate);

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

        QuestionTitleContentVM title = title(101, "{\"titleContent\":\"<p>题干 **A**</p>\"}");
        when(questionService.selectTitleContentByQuestionIds(Collections.singletonList(101)))
                .thenReturn(Collections.singletonList(title));

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
        verify(questionService, times(1)).selectTitleContentByQuestionIds(Collections.singletonList(101));
        verify(questionService, never()).selectById(anyInt());
        verify(textContentService, never()).selectById(anyInt());
    }

    @Test
    public void wrongQuestionPageDeduplicatesIdsAndHandlesMissingTitleRows() {
        QuestionPageStudentResponseVM first = row(13, 101);
        QuestionPageStudentResponseVM duplicate = row(14, 101);
        QuestionPageStudentResponseVM missing = row(15, 102);
        when(answerService.studentWrongQuestionPage(any()))
                .thenReturn(new PageInfo<>(Arrays.asList(first, duplicate, missing)));
        when(questionService.selectTitleContentByQuestionIds(Arrays.asList(101, 102)))
                .thenReturn(Arrays.asList(
                        title(101, "{\"titleContent\":\"<p>first</p>\"}"),
                        title(101, "{\"titleContent\":\"<p>ignored duplicate</p>\"}")));

        QuestionPageStudentRequestVM request = new QuestionPageStudentRequestVM();
        request.setPageIndex(1);
        request.setPageSize(10);
        RestResponse<PageInfo<QuestionPageStudentResponseVM>> response = controller.wrongQuestionPage(request);

        assertEquals("first", response.getResponse().getList().get(0).getShortTitle());
        assertEquals("first", response.getResponse().getList().get(1).getShortTitle());
        assertEquals("", response.getResponse().getList().get(2).getShortTitle());
        verify(questionService, times(1)).selectTitleContentByQuestionIds(Arrays.asList(101, 102));
    }

    @Test
    public void wrongQuestionPageWithEmptyPageDoesNotQueryTitles() {
        when(answerService.studentWrongQuestionPage(any()))
                .thenReturn(new PageInfo<>(Collections.emptyList()));

        QuestionPageStudentRequestVM request = new QuestionPageStudentRequestVM();
        request.setPageIndex(1);
        request.setPageSize(10);
        RestResponse<PageInfo<QuestionPageStudentResponseVM>> response = controller.wrongQuestionPage(request);

        assertEquals(0, response.getResponse().getList().size());
        verify(questionService, never()).selectTitleContentByQuestionIds(any());
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

    @Test
    public void workspaceReturnsDetailCorrectionAndFormattedWrongHistory() {
        ExamPaperQuestionCustomerAnswer answer = new ExamPaperQuestionCustomerAnswer();
        answer.setId(13);
        answer.setCreateUser(7);
        answer.setQuestionId(101);
        answer.setDoRight(false);
        Question question = new Question();
        question.setId(101);
        QuestionCorrectionRecordVM correction = new QuestionCorrectionRecordVM();
        correction.setId(41);
        correction.setReviewStatus("REJECTED");
        WrongQuestionWorkspaceData data = workspaceData(answer, question, correction);
        when(answerService.selectWrongQuestionWorkspace(13, 7)).thenReturn(data);

        ExamPaperSubmitItemVM answerVM = new ExamPaperSubmitItemVM();
        answerVM.setId(13);
        when(answerService.examPaperQuestionCustomerAnswerToVM(answer, "answer-json")).thenReturn(answerVM);
        QuestionEditRequestVM questionVM = new QuestionEditRequestVM();
        questionVM.setId(101);
        when(questionService.getQuestionEditRequestVM(question, "question-json")).thenReturn(questionVM);

        QuestionWrongHistoryVM history = new QuestionWrongHistoryVM();
        history.setCustomerAnswerId(13);
        history.setRawUserScore(85);
        history.setCreateTime(new Date(0));
        when(answerService.studentWrongQuestionHistory(7, 101)).thenReturn(Collections.singletonList(history));

        RestResponse<WrongQuestionWorkspaceVM> response = controller.workspace(13);

        assertEquals(1, response.getCode());
        assertEquals(Integer.valueOf(101), response.getResponse().getQuestionVM().getId());
        assertEquals(Integer.valueOf(13), response.getResponse().getQuestionAnswerVM().getId());
        assertEquals(Integer.valueOf(41), response.getResponse().getCorrection().getId());
        assertEquals("REJECTED", response.getResponse().getCorrection().getReviewStatus());
        assertEquals("8.5", response.getResponse().getWrongHistory().get(0).getUserScore());
        assertEquals(DateTimeUtil.dateFormat(new Date(0)), response.getResponse().getWrongHistory().get(0).getCreateTimeText());
        verify(answerService).selectWrongQuestionWorkspace(13, 7);
        verify(answerService).studentWrongQuestionHistory(7, 101);
        verify(answerService, never()).selectById(13);
        verify(answerService, never()).examPaperQuestionCustomerAnswerToVM(answer);
        verify(questionService, never()).getQuestionEditRequestVM(101);
        assertEquals(0, jdbcTemplate.getCalls("queryForList").size());
    }

    @Test
    public void workspaceRejectsOtherUsersAnswerBeforeLoadingDetails() {
        when(answerService.selectWrongQuestionWorkspace(13, 7)).thenReturn(null);

        RestResponse<WrongQuestionWorkspaceVM> response = controller.workspace(13);

        assertEquals(2, response.getCode());
        assertNull(response.getResponse());
        verify(answerService).selectWrongQuestionWorkspace(13, 7);
        verify(answerService, never()).examPaperQuestionCustomerAnswerToVM(any(), any());
        verify(answerService, never()).studentWrongQuestionHistory(anyInt(), anyInt());
        verify(questionService, never()).getQuestionEditRequestVM(any(), any());
        assertEquals(0, jdbcTemplate.getCalls("queryForList").size());
    }

    @Test
    public void workspaceRejectsCorrectAnswer() {
        ExamPaperQuestionCustomerAnswer answer = new ExamPaperQuestionCustomerAnswer();
        answer.setId(13);
        answer.setCreateUser(7);
        answer.setQuestionId(101);
        answer.setDoRight(true);
        WrongQuestionWorkspaceData data = workspaceData(answer, new Question(), null);
        when(answerService.selectWrongQuestionWorkspace(13, 7)).thenReturn(data);

        RestResponse<WrongQuestionWorkspaceVM> response = controller.workspace(13);

        assertEquals(2, response.getCode());
        verify(answerService, never()).examPaperQuestionCustomerAnswerToVM(any(), any());
        verify(answerService, never()).studentWrongQuestionHistory(anyInt(), anyInt());
    }

    private QuestionPageStudentResponseVM row(Integer answerId, Integer questionId) {
        QuestionPageStudentResponseVM row = new QuestionPageStudentResponseVM();
        row.setId(answerId);
        row.setLatestCustomerAnswerId(answerId);
        row.setQuestionId(questionId);
        return row;
    }

    private QuestionTitleContentVM title(Integer questionId, String content) {
        QuestionTitleContentVM vm = new QuestionTitleContentVM();
        vm.setQuestionId(questionId);
        vm.setContent(content);
        return vm;
    }

    private WrongQuestionWorkspaceData workspaceData(ExamPaperQuestionCustomerAnswer answer,
                                                     Question question,
                                                     QuestionCorrectionRecordVM correction) {
        WrongQuestionWorkspaceData data = new WrongQuestionWorkspaceData();
        data.setCustomerAnswer(answer);
        data.setQuestion(question);
        data.setQuestionContent("question-json");
        data.setAnswerContent("answer-json");
        data.setCorrection(correction);
        return data;
    }

    private User user() {
        User user = new User();
        user.setId(7);
        return user;
    }
}
