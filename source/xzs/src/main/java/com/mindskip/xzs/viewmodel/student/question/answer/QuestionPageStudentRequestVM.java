package com.mindskip.xzs.viewmodel.student.question.answer;

import com.mindskip.xzs.base.BasePage;

public class QuestionPageStudentRequestVM extends BasePage {
    private Integer createUser;

    private String correctionStatus;

    public Integer getCreateUser() {
        return createUser;
    }

    public void setCreateUser(Integer createUser) {
        this.createUser = createUser;
    }

    public String getCorrectionStatus() {
        return correctionStatus;
    }

    public void setCorrectionStatus(String correctionStatus) {
        this.correctionStatus = correctionStatus;
    }
}
