package com.mindskip.xzs.viewmodel.student.question.correction;

public class QuestionCorrectionSubmitResponseVM {

    private Integer customerAnswerId;
    private Integer correctionId;
    private String reviewStatus;

    public QuestionCorrectionSubmitResponseVM(Integer customerAnswerId, Integer correctionId, String reviewStatus) {
        this.customerAnswerId = customerAnswerId;
        this.correctionId = correctionId;
        this.reviewStatus = reviewStatus;
    }

    public Integer getCustomerAnswerId() {
        return customerAnswerId;
    }

    public void setCustomerAnswerId(Integer customerAnswerId) {
        this.customerAnswerId = customerAnswerId;
    }

    public Integer getCorrectionId() {
        return correctionId;
    }

    public void setCorrectionId(Integer correctionId) {
        this.correctionId = correctionId;
    }

    public String getReviewStatus() {
        return reviewStatus;
    }

    public void setReviewStatus(String reviewStatus) {
        this.reviewStatus = reviewStatus;
    }
}
