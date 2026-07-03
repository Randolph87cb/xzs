package com.mindskip.xzs.viewmodel.student.exam;

import javax.validation.constraints.NotNull;

public class SmartTrainingCreateRequestVM {

    @NotNull
    private Integer subjectId;

    public Integer getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(Integer subjectId) {
        this.subjectId = subjectId;
    }
}
