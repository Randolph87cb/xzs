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

@RestController("AdminQuestionReviewController")
@RequestMapping(value = "/api/admin/questionReview")
public class QuestionReviewController extends BaseApiController {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public QuestionReviewController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @RequestMapping(value = "/page", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> page(@RequestBody QuestionReviewPageRequest request) {
        int pageIndex = request.getPageIndex() == null || request.getPageIndex() < 1 ? 1 : request.getPageIndex();
        int pageSize = request.getPageSize() == null || request.getPageSize() < 1 ? 20 : request.getPageSize();
        int offset = (pageIndex - 1) * pageSize;

        StringBuilder where = new StringBuilder(" where q.deleted = false and q.status = 1 ");
        Map<String, Object> params = new HashMap<>();
        if (request.getSubjectId() != null) {
            where.append(" and q.subject_id = :subjectId ");
            params.put("subjectId", request.getSubjectId());
        }
        if (StringUtils.isNotBlank(request.getKnowledgePoint())) {
            where.append(" and q.knowledge_point = :knowledgePoint ");
            params.put("knowledgePoint", request.getKnowledgePoint().trim());
        }

        String whereSql = where.toString()
                .replace(":subjectId", params.containsKey("subjectId") ? String.valueOf(params.get("subjectId")) : "null")
                .replace(":knowledgePoint", params.containsKey("knowledgePoint") ? "'" + StringUtils.replace(String.valueOf(params.get("knowledgePoint")), "'", "''") + "'" : "null");

        Integer total = jdbcTemplate.queryForObject("select count(*) from t_question q " + whereSql, Integer.class);
        List<Map<String, Object>> list = jdbcTemplate.queryForList(
                "select q.id, q.subject_id, q.question_type, q.knowledge_point, " +
                        "tc.content::jsonb ->> 'titleContent' as title, " +
                        "tc.content::jsonb ->> 'analyze' as analyze, " +
                        "coalesce((select max(review_round) from t_question_review_record r where r.deleted = false and r.question_id = q.id and r.review_type = 'ANALYSIS'), 0) as analysis_review_round, " +
                        "coalesce((select max(review_round) from t_question_review_record r where r.deleted = false and r.question_id = q.id and r.review_type = 'KNOWLEDGE_POINT'), 0) as knowledge_review_round " +
                        "from t_question q join t_text_content tc on tc.id = q.info_text_content_id " +
                        whereSql +
                        " order by q.id desc limit ? offset ?",
                pageSize,
                offset);

        Map<String, Object> result = new HashMap<>();
        result.put("list", list);
        result.put("total", total == null ? 0 : total);
        result.put("pageIndex", pageIndex);
        result.put("pageSize", pageSize);
        return RestResponse.ok(result);
    }

    @RequestMapping(value = "/select/{questionId}", method = RequestMethod.POST)
    public RestResponse<Map<String, Object>> select(@PathVariable Integer questionId) {
        List<Map<String, Object>> questions = jdbcTemplate.queryForList(
                "select q.id, q.subject_id, q.question_type, q.knowledge_point, q.correct, " +
                        "tc.content::jsonb ->> 'titleContent' as title, " +
                        "tc.content::jsonb ->> 'analyze' as analyze, " +
                        "tc.content::jsonb -> 'questionItemObjects' as items " +
                        "from t_question q join t_text_content tc on tc.id = q.info_text_content_id " +
                        "where q.deleted = false and q.id = ?",
                questionId);
        if (questions.isEmpty()) {
            return RestResponse.fail(2, "题目不存在");
        }
        Map<String, Object> result = new HashMap<>(questions.get(0));
        result.put("reviewRecords", reviewRecords(questionId));
        return RestResponse.ok(result);
    }

    @RequestMapping(value = "/analysis/edit", method = RequestMethod.POST)
    @Transactional
    public RestResponse editAnalysis(@RequestBody QuestionReviewEditRequest request) {
        if (request.getQuestionId() == null) {
            return RestResponse.fail(2, "题目不能为空");
        }
        if (StringUtils.isBlank(request.getAfterValue())) {
            return RestResponse.fail(2, "解析不能为空");
        }
        Integer round = reviewRound(request.getReviewRound());
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select q.info_text_content_id, tc.content::jsonb ->> 'analyze' as before_value " +
                        "from t_question q join t_text_content tc on tc.id = q.info_text_content_id " +
                        "where q.deleted = false and q.id = ?",
                request.getQuestionId());
        if (rows.isEmpty()) {
            return RestResponse.fail(2, "题目不存在");
        }
        String beforeValue = (String) rows.get(0).get("before_value");
        Integer textContentId = (Integer) rows.get(0).get("info_text_content_id");
        jdbcTemplate.update(
                "update t_text_content set content = jsonb_set(content::jsonb, '{analyze}', to_jsonb(?::text), true)::text where id = ?",
                request.getAfterValue(),
                textContentId);
        insertReviewRecord(request.getQuestionId(), "ANALYSIS", round, beforeValue, request.getAfterValue(), request.getReviewComment());
        return RestResponse.ok();
    }

    @RequestMapping(value = "/knowledge/edit", method = RequestMethod.POST)
    @Transactional
    public RestResponse editKnowledgePoint(@RequestBody QuestionReviewEditRequest request) {
        if (request.getQuestionId() == null) {
            return RestResponse.fail(2, "题目不能为空");
        }
        if (StringUtils.isBlank(request.getAfterValue())) {
            return RestResponse.fail(2, "知识点不能为空");
        }
        Integer round = reviewRound(request.getReviewRound());
        String knowledgePoint = request.getAfterValue().trim();
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select q.info_text_content_id, q.knowledge_point as before_value " +
                        "from t_question q where q.deleted = false and q.id = ?",
                request.getQuestionId());
        if (rows.isEmpty()) {
            return RestResponse.fail(2, "题目不存在");
        }
        String beforeValue = (String) rows.get(0).get("before_value");
        Integer textContentId = (Integer) rows.get(0).get("info_text_content_id");
        jdbcTemplate.update("update t_question set knowledge_point = ? where id = ?", knowledgePoint, request.getQuestionId());
        jdbcTemplate.update(
                "update t_text_content set content = jsonb_set(content::jsonb, '{knowledgePoint}', to_jsonb(?::text), true)::text where id = ?",
                knowledgePoint,
                textContentId);
        insertReviewRecord(request.getQuestionId(), "KNOWLEDGE_POINT", round, beforeValue, knowledgePoint, request.getReviewComment());
        return RestResponse.ok();
    }

    @RequestMapping(value = "/knowledgePointDistribution/{subjectId}", method = RequestMethod.POST)
    public RestResponse<List<Map<String, Object>>> knowledgePointDistribution(@PathVariable Integer subjectId) {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select q.knowledge_point, count(*) as question_count, " +
                        "count(case when exists (select 1 from t_question_review_record r where r.deleted = false and r.question_id = q.id and r.review_type = 'KNOWLEDGE_POINT') then 1 end) as reviewed_count, " +
                        "count(case when not exists (select 1 from t_question_review_record r where r.deleted = false and r.question_id = q.id and r.review_type = 'KNOWLEDGE_POINT') then 1 end) as unreviewed_count " +
                        "from t_question q " +
                        "where q.deleted = false and q.status = 1 and q.subject_id = ? and q.knowledge_point is not null and q.knowledge_point <> '' " +
                        "group by q.knowledge_point order by question_count desc, q.knowledge_point",
                subjectId);
        return RestResponse.ok(rows);
    }

    private List<Map<String, Object>> reviewRecords(Integer questionId) {
        return jdbcTemplate.queryForList(
                "select id, question_id, review_type, review_round, before_value, after_value, reviewer_id, reviewer_name, review_comment, create_time " +
                        "from t_question_review_record where deleted = false and question_id = ? order by create_time desc, id desc",
                questionId);
    }

    private void insertReviewRecord(Integer questionId, String reviewType, Integer reviewRound, String beforeValue, String afterValue, String reviewComment) {
        User user = getCurrentUser();
        jdbcTemplate.update(
                "insert into t_question_review_record (question_id, review_type, review_round, before_value, after_value, reviewer_id, reviewer_name, review_comment, create_time, deleted) " +
                        "values (?, ?, ?, ?, ?, ?, ?, ?, now(), false)",
                questionId,
                reviewType,
                reviewRound,
                beforeValue,
                afterValue,
                user.getId(),
                StringUtils.defaultIfBlank(user.getRealName(), user.getUserName()),
                reviewComment);
    }

    private Integer reviewRound(Integer reviewRound) {
        return reviewRound == null || reviewRound < 1 ? 1 : reviewRound;
    }

    public static class QuestionReviewPageRequest {
        private Integer subjectId;
        private String knowledgePoint;
        private Integer pageIndex;
        private Integer pageSize;

        public Integer getSubjectId() {
            return subjectId;
        }

        public void setSubjectId(Integer subjectId) {
            this.subjectId = subjectId;
        }

        public String getKnowledgePoint() {
            return knowledgePoint;
        }

        public void setKnowledgePoint(String knowledgePoint) {
            this.knowledgePoint = knowledgePoint;
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

    public static class QuestionReviewEditRequest {
        private Integer questionId;
        private Integer reviewRound;
        private String afterValue;
        private String reviewComment;

        public Integer getQuestionId() {
            return questionId;
        }

        public void setQuestionId(Integer questionId) {
            this.questionId = questionId;
        }

        public Integer getReviewRound() {
            return reviewRound;
        }

        public void setReviewRound(Integer reviewRound) {
            this.reviewRound = reviewRound;
        }

        public String getAfterValue() {
            return afterValue;
        }

        public void setAfterValue(String afterValue) {
            this.afterValue = afterValue;
        }

        public String getReviewComment() {
            return reviewComment;
        }

        public void setReviewComment(String reviewComment) {
            this.reviewComment = reviewComment;
        }
    }
}
