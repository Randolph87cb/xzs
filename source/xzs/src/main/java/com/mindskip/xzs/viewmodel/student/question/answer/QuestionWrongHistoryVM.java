package com.mindskip.xzs.viewmodel.student.question.answer;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonIgnore;

import java.util.Date;

public class QuestionWrongHistoryVM {

    private Integer customerAnswerId;

    private Integer examPaperAnswerId;

    private Integer examPaperId;

    private String paperName;

    private Date createTime;

    private String createTimeText;

    @JsonIgnore
    private Integer rawUserScore;

    private String userScore;

    @JsonProperty("correction_status")
    private String correctionStatus;

    @JsonProperty("review_comment")
    private String reviewComment;

    public Integer getCustomerAnswerId() {
        return customerAnswerId;
    }

    public void setCustomerAnswerId(Integer customerAnswerId) {
        this.customerAnswerId = customerAnswerId;
    }

    public Integer getExamPaperAnswerId() {
        return examPaperAnswerId;
    }

    public void setExamPaperAnswerId(Integer examPaperAnswerId) {
        this.examPaperAnswerId = examPaperAnswerId;
    }

    public Integer getExamPaperId() {
        return examPaperId;
    }

    public void setExamPaperId(Integer examPaperId) {
        this.examPaperId = examPaperId;
    }

    public String getPaperName() {
        return paperName;
    }

    public void setPaperName(String paperName) {
        this.paperName = paperName;
    }

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public String getCreateTimeText() {
        return createTimeText;
    }

    public void setCreateTimeText(String createTimeText) {
        this.createTimeText = createTimeText;
    }

    public Integer getRawUserScore() {
        return rawUserScore;
    }

    public void setRawUserScore(Integer rawUserScore) {
        this.rawUserScore = rawUserScore;
    }

    public String getUserScore() {
        return userScore;
    }

    public void setUserScore(String userScore) {
        this.userScore = userScore;
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
