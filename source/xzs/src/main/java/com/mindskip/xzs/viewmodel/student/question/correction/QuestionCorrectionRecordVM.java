package com.mindskip.xzs.viewmodel.student.question.correction;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.Date;
import java.util.Map;

public class QuestionCorrectionRecordVM {

    private Integer id;

    @JsonProperty("question_id")
    private Integer questionId;

    @JsonProperty("customer_answer_id")
    private Integer customerAnswerId;

    @JsonProperty("student_wrong_reason")
    private String studentWrongReason;

    @JsonProperty("student_correct_thinking")
    private String studentCorrectThinking;

    @JsonProperty("review_status")
    private String reviewStatus;

    @JsonProperty("reviewer_name")
    private String reviewerName;

    @JsonProperty("review_comment")
    private String reviewComment;

    @JsonProperty("resubmit_count")
    private Integer resubmitCount;

    @JsonProperty("submit_time")
    private Date submitTime;

    @JsonProperty("review_time")
    private Date reviewTime;

    public static QuestionCorrectionRecordVM from(Map<String, Object> row) {
        QuestionCorrectionRecordVM vm = new QuestionCorrectionRecordVM();
        vm.setId(integerValue(row.get("id")));
        vm.setQuestionId(integerValue(row.get("question_id")));
        vm.setCustomerAnswerId(integerValue(row.get("customer_answer_id")));
        vm.setStudentWrongReason((String) row.get("student_wrong_reason"));
        vm.setStudentCorrectThinking((String) row.get("student_correct_thinking"));
        vm.setReviewStatus((String) row.get("review_status"));
        vm.setReviewerName((String) row.get("reviewer_name"));
        vm.setReviewComment((String) row.get("review_comment"));
        vm.setResubmitCount(integerValue(row.get("resubmit_count")));
        vm.setSubmitTime((Date) row.get("submit_time"));
        vm.setReviewTime((Date) row.get("review_time"));
        return vm;
    }

    private static Integer integerValue(Object value) {
        return value instanceof Number ? ((Number) value).intValue() : null;
    }

    public Integer getId() {
        return id;
    }

    public void setId(Integer id) {
        this.id = id;
    }

    public Integer getQuestionId() {
        return questionId;
    }

    public void setQuestionId(Integer questionId) {
        this.questionId = questionId;
    }

    public Integer getCustomerAnswerId() {
        return customerAnswerId;
    }

    public void setCustomerAnswerId(Integer customerAnswerId) {
        this.customerAnswerId = customerAnswerId;
    }

    public String getStudentWrongReason() {
        return studentWrongReason;
    }

    public void setStudentWrongReason(String studentWrongReason) {
        this.studentWrongReason = studentWrongReason;
    }

    public String getStudentCorrectThinking() {
        return studentCorrectThinking;
    }

    public void setStudentCorrectThinking(String studentCorrectThinking) {
        this.studentCorrectThinking = studentCorrectThinking;
    }

    public String getReviewStatus() {
        return reviewStatus;
    }

    public void setReviewStatus(String reviewStatus) {
        this.reviewStatus = reviewStatus;
    }

    public String getReviewerName() {
        return reviewerName;
    }

    public void setReviewerName(String reviewerName) {
        this.reviewerName = reviewerName;
    }

    public String getReviewComment() {
        return reviewComment;
    }

    public void setReviewComment(String reviewComment) {
        this.reviewComment = reviewComment;
    }

    public Integer getResubmitCount() {
        return resubmitCount;
    }

    public void setResubmitCount(Integer resubmitCount) {
        this.resubmitCount = resubmitCount;
    }

    public Date getSubmitTime() {
        return submitTime;
    }

    public void setSubmitTime(Date submitTime) {
        this.submitTime = submitTime;
    }

    public Date getReviewTime() {
        return reviewTime;
    }

    public void setReviewTime(Date reviewTime) {
        this.reviewTime = reviewTime;
    }
}
