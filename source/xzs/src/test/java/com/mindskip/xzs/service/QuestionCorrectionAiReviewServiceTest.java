package com.mindskip.xzs.service;

import com.mindskip.xzs.controller.support.RecordingJdbcTemplate;
import org.junit.Test;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class QuestionCorrectionAiReviewServiceTest {

    @Test
    public void preReviewSkippedRecordDoesNotChangeCorrectionReviewStatus() {
        RecordingJdbcTemplate jdbcTemplate = new RecordingJdbcTemplate();
        QuestionCorrectionAiReviewService service = new QuestionCorrectionAiReviewService(jdbcTemplate, "test-secret");
        jdbcTemplate.addQueryForListResult(Collections.singletonList(contextWithoutTeacher()));
        jdbcTemplate.addQueryForListResult(Collections.singletonList(aiReview("SKIPPED")));

        Map<String, Object> result = service.preReview(3, "MANUAL_SINGLE");

        assertEquals("SKIPPED", result.get("status"));
        assertEquals(0, jdbcTemplate.getCalls("update").size());
        assertTrue(jdbcTemplate.getCalls("queryForList").get(1).getSql()
                .contains("insert into t_question_correction_ai_review_record"));
    }

    private Map<String, Object> contextWithoutTeacher() {
        Map<String, Object> row = new HashMap<>();
        row.put("id", 3);
        row.put("teacher_user_id", null);
        return row;
    }

    private Map<String, Object> aiReview(String status) {
        Map<String, Object> row = new HashMap<>();
        row.put("status", status);
        return row;
    }
}
