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

public class QuestionReviewControllerTest {

    private RecordingJdbcTemplate jdbcTemplate;
    private QuestionReviewController controller;

    @Before
    public void setUp() {
        jdbcTemplate = new RecordingJdbcTemplate();
        controller = new QuestionReviewController(jdbcTemplate);

        WebContext webContext = mock(WebContext.class);
        when(webContext.getCurrentUser()).thenReturn(user(9, "reviewer", "Reviewer"));
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void editAnalysisUsesNextReviewRoundAndIgnoresRequestedReviewRound() {
        Map<String, Object> question = new HashMap<>();
        question.put("info_text_content_id", 21);
        question.put("before_value", "old analyze");
        jdbcTemplate.addQueryForListResult(Collections.singletonList(question));
        jdbcTemplate.addQueryForObjectResult(2);

        QuestionReviewController.QuestionReviewEditRequest request = new QuestionReviewController.QuestionReviewEditRequest();
        request.setQuestionId(7);
        request.setReviewRound(99);
        request.setAfterValue("new analyze");
        request.setReviewComment("fixed");

        RestResponse response = controller.editAnalysis(request);

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call insert = jdbcTemplate.getCalls("update").get(1);
        assertTrue(insert.getSql().contains("insert into t_question_review_record"));
        assertArrayEquals(new Object[]{
                7, "ANALYSIS", 2, "old analyze", "new analyze", 9, "Reviewer", "fixed"
        }, insert.getArgs());
    }

    @Test
    public void pageAddsUnreviewedFilterSqlAndReviewTypeParameter() {
        jdbcTemplate.addQueryForObjectResult(0);
        jdbcTemplate.addQueryForListResult(Collections.<Map<String, Object>>emptyList());

        QuestionReviewController.QuestionReviewPageRequest request = new QuestionReviewController.QuestionReviewPageRequest();
        request.setReviewType("ANALYSIS");
        request.setReviewStatus("UNREVIEWED");
        request.setPageIndex(2);
        request.setPageSize(5);

        RestResponse<Map<String, Object>> response = controller.page(request);

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call count = jdbcTemplate.getCalls("queryForObject").get(0);
        assertTrue(count.getSql().contains("review_type = ?"));
        assertTrue(count.getSql().contains("= 0"));
        assertArrayEquals(new Object[]{"ANALYSIS"}, count.getArgs());

        RecordingJdbcTemplate.Call list = jdbcTemplate.getCalls("queryForList").get(0);
        assertTrue(list.getSql().contains("review_type = ?"));
        assertTrue(list.getSql().contains("= 0"));
        assertArrayEquals(new Object[]{"ANALYSIS", 5, 5}, list.getArgs());
    }

    @Test
    public void pageAddsReviewedAtLeastOnceFilterSqlAcrossReviewTypes() {
        jdbcTemplate.addQueryForObjectResult(0);
        jdbcTemplate.addQueryForListResult(Collections.<Map<String, Object>>emptyList());

        QuestionReviewController.QuestionReviewPageRequest request = new QuestionReviewController.QuestionReviewPageRequest();
        request.setReviewStatus("REVIEWED_AT_LEAST_ONCE");
        request.setPageIndex(1);
        request.setPageSize(20);

        RestResponse<Map<String, Object>> response = controller.page(request);

        assertEquals(1, response.getCode());
        RecordingJdbcTemplate.Call count = jdbcTemplate.getCalls("queryForObject").get(0);
        assertTrue(count.getSql().contains("greatest("));
        assertTrue(count.getSql().contains(">= 1"));
        assertArrayEquals(new Object[]{}, count.getArgs());

        RecordingJdbcTemplate.Call list = jdbcTemplate.getCalls("queryForList").get(0);
        assertTrue(list.getSql().contains("greatest("));
        assertTrue(list.getSql().contains(">= 1"));
        assertArrayEquals(new Object[]{20, 0}, list.getArgs());
    }

    private User user(Integer id, String userName, String realName) {
        User user = new User();
        user.setId(id);
        user.setUserName(userName);
        user.setRealName(realName);
        return user;
    }
}
