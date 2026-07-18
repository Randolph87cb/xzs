package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.QuestionCorrectionAiReviewService;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController("AdminQuestionCorrectionController")
@RequestMapping(value = "/api/admin/questionCorrection")
public class QuestionCorrectionController extends BaseApiController {

    private final JdbcTemplate jdbcTemplate;
    private final ClassScopeService classScopeService;
    private final QuestionCorrectionAiReviewService questionCorrectionAiReviewService;

    @Autowired
    public QuestionCorrectionController(JdbcTemplate jdbcTemplate, ClassScopeService classScopeService, QuestionCorrectionAiReviewService questionCorrectionAiReviewService) {
        this.jdbcTemplate = jdbcTemplate;
        this.classScopeService = classScopeService;
        this.questionCorrectionAiReviewService = questionCorrectionAiReviewService;
    }

    @RequestMapping(value = "/page", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> page(@RequestBody QuestionCorrectionPageRequest request) {
        int pageIndex = request.getPageIndex() == null || request.getPageIndex() < 1 ? 1 : request.getPageIndex();
        int pageSize = request.getPageSize() == null || request.getPageSize() < 1 ? 20 : request.getPageSize();
        int offset = (pageIndex - 1) * pageSize;
        User currentUser = getCurrentUser();
        List<Object> args = new ArrayList<>();
        String filter = pageFilterSql(request, currentUser, args);

        Integer total = jdbcTemplate.queryForObject(countBaseSql() + filter, Integer.class, args.toArray());
        args.add(pageSize);
        args.add(offset);
        List<Map<String, Object>> list = jdbcTemplate.queryForList(pageSql(filter), args.toArray());

        Map<String, Object> result = new HashMap<>();
        result.put("list", list);
        result.put("total", total == null ? 0 : total);
        result.put("pageIndex", pageIndex);
        result.put("pageSize", pageSize);
        return RestResponse.ok(result);
    }

    @RequestMapping(value = "/select/{id}", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> select(@PathVariable Integer id) {
        List<Object> args = new ArrayList<>();
        QuestionCorrectionPageRequest request = new QuestionCorrectionPageRequest();
        String filter = pageFilterSql(request, getCurrentUser(), args);
        args.add(id);
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(pageBaseSql() + filter + " and c.id = ?", args.toArray());
        if (rows.isEmpty()) {
            return RestResponse.fail(2, "改错记录不存在");
        }
        Map<String, Object> result = new HashMap<>(rows.get(0));
        result.put("aiReview", latestAiReview(result));
        result.put("reviewRecords", jdbcTemplate.queryForList(
                "select * from t_question_correction_review_record where correction_id = ? order by create_time desc, id desc",
                id));
        return RestResponse.ok(result);
    }

    @RequestMapping(value = "/ai/config/select", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> selectAiConfig() {
        User currentUser = getCurrentUser();
        if (!classScopeService.isTeacher(currentUser)) {
            return RestResponse.fail(2, "AI 预审配置仅班级负责老师可维护");
        }
        return RestResponse.ok(questionCorrectionAiReviewService.selectConfig(currentUser.getId()));
    }

    @RequestMapping(value = "/ai/config/edit", method = RequestMethod.POST)
    public RestResponse editAiConfig(@RequestBody QuestionCorrectionAiReviewService.SaveConfigRequest request) {
        User currentUser = getCurrentUser();
        if (!classScopeService.isTeacher(currentUser)) {
            return RestResponse.fail(2, "AI 预审配置仅班级负责老师可维护");
        }
        String error = questionCorrectionAiReviewService.saveConfig(currentUser.getId(), request);
        if (StringUtils.isNotBlank(error)) {
            return RestResponse.fail(2, error);
        }
        return RestResponse.ok();
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
        List<Object> args = new ArrayList<>();
        String filter = correctionScopeSql(getCurrentUser(), args);
        args.add(request.getId());
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select c.* from t_question_correction_record c join t_user u on u.id = c.user_id where c.deleted = false " + filter + " and c.id = ?",
                args.toArray());
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

    private String countBaseSql() {
        return "select count(*) " +
                "from t_question_correction_record c " +
                "join t_user u on u.id = c.user_id " +
                "where c.deleted = false ";
    }

    private String pageBaseSql() {
        return "select c.*, u.user_name, u.real_name, q.question_type, q.correct, a.answer as student_answer, " +
                "tc.content::jsonb ->> 'titleContent' as title, " +
                "tc.content::jsonb ->> 'questionItemObjects' as items, " +
                "tc.content::jsonb ->> 'analyze' as analyze, " +
                "ai.status as ai_review_status, ai.review_result as ai_review_result, ai.review_comment as ai_review_comment, " +
                "ai.confidence as ai_review_confidence, ai.reason as ai_review_reason, ai.error_message as ai_review_error_message, " +
                "ai.finish_time as ai_review_time " +
                "from t_question_correction_record c " +
                "join t_user u on u.id = c.user_id " +
                "join t_question q on q.id = c.question_id " +
                "join t_text_content tc on tc.id = q.info_text_content_id " +
                "join t_exam_paper_question_customer_answer a on a.id = c.customer_answer_id " +
                "left join lateral (" +
                "  select status, review_result, review_comment, confidence, reason, error_message, finish_time " +
                "  from t_question_correction_ai_review_record ar " +
                "  where ar.correction_id = c.id " +
                "  order by ar.create_time desc, ar.id desc limit 1" +
                ") ai on true " +
                "where c.deleted = false ";
    }

    private Map<String, Object> latestAiReview(Map<String, Object> row) {
        if (row.get("ai_review_status") == null) {
            return null;
        }
        Map<String, Object> aiReview = new HashMap<>();
        aiReview.put("status", row.get("ai_review_status"));
        aiReview.put("reviewResult", row.get("ai_review_result"));
        aiReview.put("reviewComment", row.get("ai_review_comment"));
        aiReview.put("confidence", row.get("ai_review_confidence"));
        aiReview.put("reason", row.get("ai_review_reason"));
        aiReview.put("errorMessage", row.get("ai_review_error_message"));
        aiReview.put("finishTime", row.get("ai_review_time"));
        return aiReview;
    }

    private String pageFilterSql(QuestionCorrectionPageRequest request, User currentUser, List<Object> args) {
        StringBuilder sql = new StringBuilder();
        if (!StringUtils.isBlank(request.getReviewStatus())) {
            sql.append(" and c.review_status = ? ");
            args.add(request.getReviewStatus());
        }
        if (request.getClassId() != null) {
            sql.append(" and coalesce(c.class_id, u.class_id) = ? ");
            args.add(request.getClassId());
        }
        sql.append(correctionScopeSql(currentUser, args));
        return sql.toString();
    }

    private String correctionScopeSql(User currentUser, List<Object> args) {
        if (!classScopeService.isTeacher(currentUser)) {
            return "";
        }
        List<Integer> classIds = classScopeService.teacherClassIds(currentUser);
        if (classIds.isEmpty()) {
            return " and 1 = 0 ";
        }
        StringBuilder sql = new StringBuilder(" and coalesce(c.class_id, u.class_id) in (");
        for (int i = 0; i < classIds.size(); i++) {
            if (i > 0) {
                sql.append(",");
            }
            sql.append("?");
            args.add(classIds.get(i));
        }
        sql.append(") ");
        return sql.toString();
    }

    public static class QuestionCorrectionPageRequest {
        private String reviewStatus;
        private Integer pageIndex;
        private Integer pageSize;
        private Integer classId;

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

        public Integer getClassId() {
            return classId;
        }

        public void setClassId(Integer classId) {
            this.classId = classId;
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
