package com.mindskip.xzs.controller.student;

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
        when(webContext.getCurrentUser()).thenReturn(user(23));
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void submitRejectsDuplicateSubmittedCorrection() {
        jdbcTemplate.addQueryForListResult(Collections.singletonList(answer()));
        jdbcTemplate.addQueryForListResult(Collections.singletonList(existing("SUBMITTED")));

        RestResponse response = controller.submit(submitRequest());

        assertEquals(2, response.getCode());
        assertEquals(0, jdbcTemplate.getCalls("update").size());
    }

    @Test
    public void submitAllowsRejectedCorrectionToBeResubmitted() {
        jdbcTemplate.addQueryForListResult(Collections.singletonList(answer()));
        jdbcTemplate.addQueryForListResult(Collections.singletonList(existing("REJECTED")));

        RestResponse response = controller.submit(submitRequest());

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call update = jdbcTemplate.getCalls("update").get(0);
        assertTrue(update.getSql().contains("review_status = 'SUBMITTED'"));
        assertTrue(update.getSql().contains("resubmit_count = coalesce(resubmit_count, 0) + 1"));
        assertArrayEquals(new Object[]{"new wrong", "new thinking", 41}, update.getArgs());
    }

    @Test
    public void submitRejectsApprovedCorrection() {
        jdbcTemplate.addQueryForListResult(Collections.singletonList(answer()));
        jdbcTemplate.addQueryForListResult(Collections.singletonList(existing("APPROVED")));

        RestResponse response = controller.submit(submitRequest());

        assertEquals(2, response.getCode());
        assertEquals(0, jdbcTemplate.getCalls("update").size());
    }

    private QuestionCorrectionController.QuestionCorrectionSubmitRequest submitRequest() {
        QuestionCorrectionController.QuestionCorrectionSubmitRequest request = new QuestionCorrectionController.QuestionCorrectionSubmitRequest();
        request.setCustomerAnswerId(13);
        request.setWrongReason("  new wrong  ");
        request.setCorrectThinking("  new thinking  ");
        return request;
    }

    private Map<String, Object> answer() {
        Map<String, Object> row = new HashMap<>();
        row.put("id", 13);
        row.put("question_id", 101);
        row.put("exam_paper_answer_id", 202);
        row.put("create_user", 23);
        return row;
    }

    private Map<String, Object> existing(String status) {
        Map<String, Object> row = new HashMap<>();
        row.put("id", 41);
        row.put("review_status", status);
        return row;
    }

    private User user(Integer id) {
        User user = new User();
        user.setId(id);
        user.setUserName("student");
        user.setRealName("Student User");
        return user;
    }
}
