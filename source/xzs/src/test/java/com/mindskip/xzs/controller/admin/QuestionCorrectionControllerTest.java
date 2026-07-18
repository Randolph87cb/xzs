package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.controller.support.RecordingJdbcTemplate;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.QuestionCorrectionAiReviewService;
import org.junit.Before;
import org.junit.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class QuestionCorrectionControllerTest {

    private RecordingJdbcTemplate jdbcTemplate;
    private ClassScopeService classScopeService;
    private QuestionCorrectionAiReviewService aiReviewService;
    private QuestionCorrectionController controller;
    private WebContext webContext;

    @Before
    public void setUp() {
        jdbcTemplate = new RecordingJdbcTemplate();
        classScopeService = mock(ClassScopeService.class);
        aiReviewService = mock(QuestionCorrectionAiReviewService.class);
        controller = new QuestionCorrectionController(jdbcTemplate, classScopeService, aiReviewService);

        webContext = mock(WebContext.class);
        when(webContext.getCurrentUser()).thenReturn(user(12, "admin", "Admin User", RoleEnum.ADMIN));
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void reviewRejectsRecordsThatAreNotSubmitted() {
        jdbcTemplate.addQueryForListResult(Collections.singletonList(correction("APPROVED")));

        RestResponse response = controller.review(reviewRequest(3, "APPROVED", "ok"));

        assertEquals(2, response.getCode());
        assertEquals(0, jdbcTemplate.getCalls("update").size());
    }

    @Test
    public void reviewApprovedUpdatesMainRecordStatusAndWritesReviewResult() {
        jdbcTemplate.addQueryForListResult(Collections.singletonList(correction("SUBMITTED")));

        RestResponse response = controller.review(reviewRequest(3, "APPROVED", "ok"));

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call mainUpdate = jdbcTemplate.getCalls("update").get(0);
        assertTrue(mainUpdate.getSql().startsWith("update t_question_correction_record"));
        assertArrayEquals(new Object[]{"APPROVED", 12, "Admin User", "ok", 3}, mainUpdate.getArgs());

        RecordingJdbcTemplate.Call reviewInsert = jdbcTemplate.getCalls("update").get(1);
        assertTrue(reviewInsert.getSql().contains("insert into t_question_correction_review_record"));
        assertTrue(reviewInsert.getSql().contains("review_result"));
        assertArrayEquals(new Object[]{
                3, "APPROVED", "student wrong", "student thinking",
                "student wrong", "student thinking", 12, "Admin User", "ok"
        }, reviewInsert.getArgs());
    }

    @Test
    public void reviewRejectedRequiresReviewComment() {
        jdbcTemplate.addQueryForListResult(Collections.singletonList(correction("SUBMITTED")));

        RestResponse response = controller.review(reviewRequest(3, "REJECTED", " "));

        assertEquals(2, response.getCode());
        assertEquals(0, jdbcTemplate.getCalls("update").size());
    }

    @Test
    public void reviewRejectedRecordsReviewCommentAndReviewResult() {
        jdbcTemplate.addQueryForListResult(Collections.singletonList(correction("SUBMITTED")));

        RestResponse response = controller.review(reviewRequest(3, "REJECTED", "needs more detail"));

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call mainUpdate = jdbcTemplate.getCalls("update").get(0);
        assertArrayEquals(new Object[]{"REJECTED", 12, "Admin User", "needs more detail", 3}, mainUpdate.getArgs());

        RecordingJdbcTemplate.Call reviewInsert = jdbcTemplate.getCalls("update").get(1);
        assertTrue(reviewInsert.getSql().contains("review_result"));
        assertArrayEquals(new Object[]{
                3, "REJECTED", "student wrong", "student thinking",
                "student wrong", "student thinking", 12, "Admin User", "needs more detail"
        }, reviewInsert.getArgs());
    }

    @Test
    public void selectIncludesQuestionItemsAndStudentAnswer() {
        Map<String, Object> row = correction("SUBMITTED");
        row.put("student_answer", "A");
        jdbcTemplate.addQueryForListResult(Collections.singletonList(row));
        jdbcTemplate.addQueryForListResult(Collections.emptyList());

        RestResponse<Map<String, Object>> response = controller.select(3);

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call detailQuery = jdbcTemplate.getCalls("queryForList").get(0);
        assertTrue(detailQuery.getSql().contains("->> 'questionItemObjects' as items"));
        assertTrue(detailQuery.getSql().contains("->> 'analyze' as analyze"));
        assertTrue(detailQuery.getSql().contains("student_answer"));
        assertEquals("A", response.getResponse().get("student_answer"));
    }

    @Test
    public void pageFiltersByLatestAiReviewStatusInCountAndListQueries() {
        QuestionCorrectionController.QuestionCorrectionPageRequest request = new QuestionCorrectionController.QuestionCorrectionPageRequest();
        request.setAiReviewStatus("FAILED");
        jdbcTemplate.addQueryForObjectResult(0);
        jdbcTemplate.addQueryForListResult(Collections.emptyList());

        RestResponse<Map<String, Object>> response = controller.page(request);

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call countQuery = jdbcTemplate.getCalls("queryForObject").get(0);
        assertTrue(countQuery.getSql().contains("left join lateral"));
        assertTrue(countQuery.getSql().contains("from t_question_correction_ai_review_record ar"));
        assertTrue(countQuery.getSql().contains("ai.status = ?"));
        assertArrayEquals(new Object[]{"FAILED"}, countQuery.getArgs());

        RecordingJdbcTemplate.Call listQuery = jdbcTemplate.getCalls("queryForList").get(0);
        assertTrue(listQuery.getSql().contains("left join lateral"));
        assertTrue(listQuery.getSql().contains("ai.status = ?"));
        assertArrayEquals(new Object[]{"FAILED", 20, 0}, listQuery.getArgs());
    }

    @Test
    public void selectAiConfigRejectsUserWithoutAiConfigPermission() {
        RestResponse<Map<String, Object>> response = controller.selectAiConfig();

        assertEquals(2, response.getCode());
        assertEquals("AI 预审配置仅老师或管理员可维护", response.getMessage());
        verify(aiReviewService, never()).selectConfig(any());
    }

    @Test
    public void editAiConfigRejectsUserWithoutAiConfigPermission() {
        RestResponse response = controller.editAiConfig(new QuestionCorrectionAiReviewService.SaveConfigRequest());

        assertEquals(2, response.getCode());
        assertEquals("AI 预审配置仅老师或管理员可维护", response.getMessage());
        verify(aiReviewService, never()).saveConfig(eq(12), any());
    }

    @Test
    public void selectAiConfigAllowsAdmin() {
        Map<String, Object> config = new HashMap<>();
        config.put("enabled", true);
        when(classScopeService.canConfigureAiReview(any())).thenReturn(true);
        when(aiReviewService.selectConfig(12)).thenReturn(config);

        RestResponse<Map<String, Object>> response = controller.selectAiConfig();

        assertEquals(1, response.getCode());
        assertEquals(config, response.getResponse());
        verify(aiReviewService).selectConfig(12);
    }

    @Test
    public void editAiConfigAllowsAdmin() {
        QuestionCorrectionAiReviewService.SaveConfigRequest request = new QuestionCorrectionAiReviewService.SaveConfigRequest();
        when(classScopeService.canConfigureAiReview(any())).thenReturn(true);

        RestResponse response = controller.editAiConfig(request);

        assertEquals(1, response.getCode());
        verify(aiReviewService).saveConfig(12, request);
    }

    @Test
    public void manualSingleAiReviewTriggersAiWithoutUpdatingReviewStatus() {
        Map<String, Object> aiReview = aiReview("SUCCESS");
        jdbcTemplate.addQueryForListResult(Collections.singletonList(correction("APPROVED")));
        when(aiReviewService.preReview(3, "MANUAL_SINGLE")).thenReturn(aiReview);

        RestResponse<Map<String, Object>> response = controller.aiReview(3);

        assertEquals(1, response.getCode());
        assertEquals(3, response.getResponse().get("correctionId"));
        assertEquals("APPROVED", response.getResponse().get("reviewStatus"));
        assertEquals(aiReview, response.getResponse().get("aiReview"));
        assertEquals(0, jdbcTemplate.getCalls("update").size());
        verify(aiReviewService).preReview(3, "MANUAL_SINGLE");
    }

    @Test
    public void batchAiReviewDefaultsToSubmittedAndAppliesTeacherScopeAndLimit() {
        when(webContext.getCurrentUser()).thenReturn(user(22, "teacher", "Teacher User", RoleEnum.TEACHER));
        when(classScopeService.isTeacher(any())).thenReturn(true);
        when(classScopeService.teacherClassIds(any())).thenReturn(Arrays.asList(101, 102));
        QuestionCorrectionController.QuestionCorrectionPageRequest request = new QuestionCorrectionController.QuestionCorrectionPageRequest();
        request.setAiReviewStatus("SKIPPED");
        jdbcTemplate.addQueryForListResult(Arrays.asList(
                correction(1, "SUBMITTED"),
                correction(2, "SUBMITTED"),
                correction(3, "APPROVED")));
        when(aiReviewService.preReview(1, "MANUAL_BATCH")).thenReturn(aiReview("SUCCESS"));
        when(aiReviewService.preReview(2, "MANUAL_BATCH")).thenReturn(aiReview("SKIPPED"));

        RestResponse<Map<String, Object>> response = controller.batchAiReview(request);

        assertEquals(1, response.getCode());
        assertEquals(1, response.getResponse().get("acceptedCount"));
        assertEquals(2, response.getResponse().get("skippedCount"));
        assertEquals(0, response.getResponse().get("failedCount"));
        assertEquals(50, response.getResponse().get("limit"));
        RecordingJdbcTemplate.Call query = jdbcTemplate.getCalls("queryForList").get(0);
        assertTrue(query.getSql().contains("left join lateral"));
        assertTrue(query.getSql().contains("c.review_status = ?"));
        assertTrue(query.getSql().contains("ai.status = ?"));
        assertTrue(query.getSql().contains("coalesce(c.class_id, u.class_id) in (?,?)"));
        assertTrue(query.getSql().contains("limit ?"));
        assertArrayEquals(new Object[]{"SUBMITTED", "SKIPPED", 101, 102, 50}, query.getArgs());
    }

    @Test
    public void manualSingleAiReviewRejectsTeacherOutOfScopeRecord() {
        when(webContext.getCurrentUser()).thenReturn(user(22, "teacher", "Teacher User", RoleEnum.TEACHER));
        when(classScopeService.isTeacher(any())).thenReturn(true);
        when(classScopeService.teacherClassIds(any())).thenReturn(Collections.singletonList(101));
        jdbcTemplate.addQueryForListResult(Collections.emptyList());

        RestResponse<Map<String, Object>> response = controller.aiReview(99);

        assertEquals(2, response.getCode());
        assertEquals("改错记录不存在", response.getMessage());
        assertArrayEquals(new Object[]{101, 99}, jdbcTemplate.getCalls("queryForList").get(0).getArgs());
        verify(aiReviewService, never()).preReview(any(), any());
    }

    private QuestionCorrectionController.QuestionCorrectionReviewRequest reviewRequest(Integer id, String result, String comment) {
        QuestionCorrectionController.QuestionCorrectionReviewRequest request = new QuestionCorrectionController.QuestionCorrectionReviewRequest();
        request.setId(id);
        request.setReviewResult(result);
        request.setReviewComment(comment);
        return request;
    }

    private Map<String, Object> correction(String status) {
        return correction(3, status);
    }

    private Map<String, Object> correction(Integer id, String status) {
        Map<String, Object> row = new HashMap<>();
        row.put("id", id);
        row.put("review_status", status);
        row.put("student_wrong_reason", "student wrong");
        row.put("student_correct_thinking", "student thinking");
        return row;
    }

    private Map<String, Object> aiReview(String status) {
        Map<String, Object> row = new HashMap<>();
        row.put("status", status);
        return row;
    }

    private User user(Integer id, String userName, String realName, RoleEnum role) {
        User user = new User();
        user.setId(id);
        user.setUserName(userName);
        user.setRealName(realName);
        user.setRole(role.getCode());
        return user;
    }
}
