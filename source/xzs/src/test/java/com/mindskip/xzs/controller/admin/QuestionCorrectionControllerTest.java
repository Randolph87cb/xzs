package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.controller.support.RecordingJdbcTemplate;
import com.mindskip.xzs.domain.User;
import org.junit.Before;
import org.junit.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class QuestionCorrectionControllerTest {

    private RecordingJdbcTemplate jdbcTemplate;
    private QuestionCorrectionController controller;

    @Before
    public void setUp() {
        jdbcTemplate = new RecordingJdbcTemplate();
        controller = new QuestionCorrectionController(jdbcTemplate);

        WebContext webContext = mock(WebContext.class);
        when(webContext.getCurrentUser()).thenReturn(user(12, "admin", "Admin User"));
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
        assertTrue(detailQuery.getSql().contains("questionItemObjects"));
        assertTrue(detailQuery.getSql().contains("student_answer"));
        assertEquals("A", response.getResponse().get("student_answer"));
    }

    private QuestionCorrectionController.QuestionCorrectionReviewRequest reviewRequest(Integer id, String result, String comment) {
        QuestionCorrectionController.QuestionCorrectionReviewRequest request = new QuestionCorrectionController.QuestionCorrectionReviewRequest();
        request.setId(id);
        request.setReviewResult(result);
        request.setReviewComment(comment);
        return request;
    }

    private Map<String, Object> correction(String status) {
        Map<String, Object> row = new HashMap<>();
        row.put("id", 3);
        row.put("review_status", status);
        row.put("student_wrong_reason", "student wrong");
        row.put("student_correct_thinking", "student thinking");
        return row;
    }

    private User user(Integer id, String userName, String realName) {
        User user = new User();
        user.setId(id);
        user.setUserName(userName);
        user.setRealName(realName);
        return user;
    }
}
