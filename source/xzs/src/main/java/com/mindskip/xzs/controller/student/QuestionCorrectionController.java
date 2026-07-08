package com.mindskip.xzs.controller.student;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController("StudentQuestionCorrectionController")
@RequestMapping(value = "/api/student/question/correction")
public class QuestionCorrectionController extends BaseApiController {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public QuestionCorrectionController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @RequestMapping(value = "/select/{customerAnswerId}", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> select(@PathVariable Integer customerAnswerId) {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select * from t_question_correction_record where deleted = false and customer_answer_id = ? and user_id = ? order by id desc limit 1",
                customerAnswerId,
                getCurrentUser().getId());
        return RestResponse.ok(rows.isEmpty() ? null : rows.get(0));
    }

    @RequestMapping(value = "/submit", method = RequestMethod.POST)
    @Transactional
    public RestResponse submit(@RequestBody QuestionCorrectionSubmitRequest request) {
        if (request.getCustomerAnswerId() == null) {
            return RestResponse.fail(2, "错题不能为空");
        }
        if (StringUtils.isBlank(request.getWrongReason())) {
            return RestResponse.fail(2, "错误原因不能为空");
        }
        if (StringUtils.isBlank(request.getCorrectThinking())) {
            return RestResponse.fail(2, "正确思路不能为空");
        }
        List<Map<String, Object>> answerRows = jdbcTemplate.queryForList(
                "select id, question_id, exam_paper_answer_id, create_user from t_exam_paper_question_customer_answer " +
                        "where id = ? and create_user = ? and do_right = false",
                request.getCustomerAnswerId(),
                getCurrentUser().getId());
        if (answerRows.isEmpty()) {
            return RestResponse.fail(2, "错题不存在");
        }

        Map<String, Object> answer = answerRows.get(0);
        List<Integer> existingIds = jdbcTemplate.queryForList(
                "select id from t_question_correction_record where deleted = false and customer_answer_id = ? and user_id = ? order by id desc limit 1",
                Integer.class,
                request.getCustomerAnswerId(),
                getCurrentUser().getId());
        if (existingIds.isEmpty()) {
            jdbcTemplate.update(
                    "insert into t_question_correction_record (user_id, question_id, exam_paper_answer_id, customer_answer_id, student_wrong_reason, student_correct_thinking, review_status, submit_time, deleted) " +
                            "values (?, ?, ?, ?, ?, ?, 'SUBMITTED', now(), false)",
                    getCurrentUser().getId(),
                    answer.get("question_id"),
                    answer.get("exam_paper_answer_id"),
                    request.getCustomerAnswerId(),
                    request.getWrongReason().trim(),
                    request.getCorrectThinking().trim());
        } else {
            jdbcTemplate.update(
                    "update t_question_correction_record set student_wrong_reason = ?, student_correct_thinking = ?, review_status = 'SUBMITTED', submit_time = now() where id = ?",
                    request.getWrongReason().trim(),
                    request.getCorrectThinking().trim(),
                    existingIds.get(0));
        }
        return RestResponse.ok();
    }

    public static class QuestionCorrectionSubmitRequest {
        private Integer customerAnswerId;
        private String wrongReason;
        private String correctThinking;

        public Integer getCustomerAnswerId() {
            return customerAnswerId;
        }

        public void setCustomerAnswerId(Integer customerAnswerId) {
            this.customerAnswerId = customerAnswerId;
        }

        public String getWrongReason() {
            return wrongReason;
        }

        public void setWrongReason(String wrongReason) {
            this.wrongReason = wrongReason;
        }

        public String getCorrectThinking() {
            return correctThinking;
        }

        public void setCorrectThinking(String correctThinking) {
            this.correctThinking = correctThinking;
        }
    }
}
