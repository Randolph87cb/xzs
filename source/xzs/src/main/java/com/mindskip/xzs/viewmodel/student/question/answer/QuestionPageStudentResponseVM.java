package com.mindskip.xzs.viewmodel.student.question.answer;


import com.fasterxml.jackson.annotation.JsonProperty;

public class QuestionPageStudentResponseVM {
    private Integer id;

    private Integer questionId;

    private Integer latestCustomerAnswerId;

    private Integer questionType;

    private String createTime;

    private String latestWrongTime;

    private String subjectName;

    private String shortTitle;

    private String knowledgePoint;

    private Integer wrongCount;

    @JsonProperty("correction_status")
    private String correctionStatus;

    @JsonProperty("review_comment")
    private String reviewComment;

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

    public Integer getLatestCustomerAnswerId() {
        return latestCustomerAnswerId;
    }

    public void setLatestCustomerAnswerId(Integer latestCustomerAnswerId) {
        this.latestCustomerAnswerId = latestCustomerAnswerId;
    }

    public Integer getQuestionType() {
        return questionType;
    }

    public void setQuestionType(Integer questionType) {
        this.questionType = questionType;
    }

    public String getCreateTime() {
        return createTime;
    }

    public void setCreateTime(String createTime) {
        this.createTime = createTime;
    }

    public String getLatestWrongTime() {
        return latestWrongTime;
    }

    public void setLatestWrongTime(String latestWrongTime) {
        this.latestWrongTime = latestWrongTime;
    }

    public String getSubjectName() {
        return subjectName;
    }

    public void setSubjectName(String subjectName) {
        this.subjectName = subjectName;
    }

    public String getShortTitle() {
        return shortTitle;
    }

    public void setShortTitle(String shortTitle) {
        this.shortTitle = shortTitle;
    }

    public String getKnowledgePoint() {
        return knowledgePoint;
    }

    public void setKnowledgePoint(String knowledgePoint) {
        this.knowledgePoint = knowledgePoint;
    }

    public Integer getWrongCount() {
        return wrongCount;
    }

    public void setWrongCount(Integer wrongCount) {
        this.wrongCount = wrongCount;
    }

    public String getCorrectionStatus() {
        return correctionStatus;
    }

    public void setCorrectionStatus(String correctionStatus) {
        this.correctionStatus = correctionStatus;
    }

    public String getReviewComment() {
        return reviewComment;
    }

    public void setReviewComment(String reviewComment) {
        this.reviewComment = reviewComment;
    }
}
