package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.User;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController("AdminQuestionCorrectionController")
@RequestMapping(value = "/api/admin/questionCorrection")
public class QuestionCorrectionController extends BaseApiController {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public QuestionCorrectionController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @RequestMapping(value = "/page", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> page(@RequestBody QuestionCorrectionPageRequest request) {
        int pageIndex = request.getPageIndex() == null || request.getPageIndex() < 1 ? 1 : request.getPageIndex();
        int pageSize = request.getPageSize() == null || request.getPageSize() < 1 ? 20 : request.getPageSize();
        int offset = (pageIndex - 1) * pageSize;
        String statusFilter = StringUtils.isBlank(request.getReviewStatus()) ? "" : " and c.review_status = ? ";
        Integer total = StringUtils.isBlank(request.getReviewStatus()) ?
                jdbcTemplate.queryForObject("select count(*) from t_question_correction_record c where c.deleted = false", Integer.class) :
                jdbcTemplate.queryForObject("select count(*) from t_question_correction_record c where c.deleted = false and c.review_status = ?", Integer.class, request.getReviewStatus());

        List<Map<String, Object>> list = StringUtils.isBlank(request.getReviewStatus()) ?
                jdbcTemplate.queryForList(pageSql(""), pageSize, offset) :
                jdbcTemplate.queryForList(pageSql(statusFilter), request.getReviewStatus(), pageSize, offset);

        Map<String, Object> result = new HashMap<>();
        result.put("list", list);
        result.put("total", total == null ? 0 : total);
        result.put("pageIndex", pageIndex);
        result.put("pageSize", pageSize);
        return RestResponse.ok(result);
    }

    @RequestMapping(value = "/select/{id}", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> select(@PathVariable Integer id) {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(pageBaseSql() + " and c.id = ?", id);
        if (rows.isEmpty()) {
            return RestResponse.fail(2, "改错记录不存在");
        }
        Map<String, Object> result = new HashMap<>(rows.get(0));
        result.put("reviewRecords", jdbcTemplate.queryForList(
                "select * from t_question_correction_review_record where correction_id = ? order by create_time desc, id desc",
                id));
        return RestResponse.ok(result);
    }

    @RequestMapping(value = "/review/edit", method = RequestMethod.POST)
    @Transactional
    public RestResponse review(@RequestBody QuestionCorrectionReviewRequest request) {
        if (request.getId() == null) {
            return RestResponse.fail(2, "改错记录不能为空");
        }
        if (!"APPROVED".equals(request.getReviewResult()) && !"REJECTED".equals(request.getReviewResult())) {
            return RestResponse.fail(2, "审核结果不正确");
        }
        if ("REJECTED".equals(request.getReviewResult()) && StringUtils.isBlank(request.getReviewComment())) {
            return RestResponse.fail(2, "审核意见不能为空");
        }
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select * from t_question_correction_record where deleted = false and id = ?",
                request.getId());
        if (rows.isEmpty()) {
            return RestResponse.fail(2, "改错记录不存在");
        }
        Map<String, Object> before = rows.get(0);
        if (!"SUBMITTED".equals(before.get("review_status"))) {
            return RestResponse.fail(2, "当前改错记录不可审核");
        }
        User user = getCurrentUser();
        String reviewerName = StringUtils.defaultIfBlank(user.getRealName(), user.getUserName());

        jdbcTemplate.update(
                "update t_question_correction_record set review_status = ?, reviewer_id = ?, reviewer_name = ?, review_comment = ?, review_time = now() where id = ?",
                request.getReviewResult(),
                user.getId(),
                reviewerName,
                request.getReviewComment(),
                request.getId());

        jdbcTemplate.update(
                "insert into t_question_correction_review_record " +
                        "(correction_id, review_result, student_wrong_reason, student_correct_thinking, before_wrong_reason, before_correct_thinking, reviewer_id, reviewer_name, review_comment, create_time) " +
                        "values (?, ?, ?, ?, ?, ?, ?, ?, ?, now())",
                request.getId(),
                request.getReviewResult(),
                before.get("student_wrong_reason"),
                before.get("student_correct_thinking"),
                before.get("student_wrong_reason"),
                before.get("student_correct_thinking"),
                user.getId(),
                reviewerName,
                request.getReviewComment());

        return RestResponse.ok();
    }

    private String pageSql(String statusFilter) {
        return pageBaseSql() + statusFilter + " order by c.submit_time desc, c.id desc limit ? offset ?";
    }

    private String pageBaseSql() {
        return "select c.*, u.user_name, u.real_name, q.question_type, q.correct, a.answer as student_answer, " +
                "tc.content::jsonb ->> 'titleContent' as title, " +
                "tc.content::jsonb -> 'questionItemObjects' as items " +
                "from t_question_correction_record c " +
                "join t_user u on u.id = c.user_id " +
                "join t_question q on q.id = c.question_id " +
                "join t_text_content tc on tc.id = q.info_text_content_id " +
                "join t_exam_paper_question_customer_answer a on a.id = c.customer_answer_id " +
                "where c.deleted = false ";
    }

    public static class QuestionCorrectionPageRequest {
        private String reviewStatus;
        private Integer pageIndex;
        private Integer pageSize;

        public String getReviewStatus() {
            return reviewStatus;
        }

        public void setReviewStatus(String reviewStatus) {
            this.reviewStatus = reviewStatus;
        }

        public Integer getPageIndex() {
            return pageIndex;
        }

        public void setPageIndex(Integer pageIndex) {
            this.pageIndex = pageIndex;
        }

        public Integer getPageSize() {
            return pageSize;
        }

        public void setPageSize(Integer pageSize) {
            this.pageSize = pageSize;
        }
    }

    public static class QuestionCorrectionReviewRequest {
        private Integer id;
        private String reviewResult;
        private String reviewComment;

        public Integer getId() {
            return id;
        }

        public void setId(Integer id) {
            this.id = id;
        }

        public String getReviewResult() {
            return reviewResult;
        }

        public void setReviewResult(String reviewResult) {
            this.reviewResult = reviewResult;
        }

        public String getReviewComment() {
            return reviewComment;
        }

        public void setReviewComment(String reviewComment) {
            this.reviewComment = reviewComment;
        }
    }
}
