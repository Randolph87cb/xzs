package com.mindskip.xzs.viewmodel.student.exam;

public class SmartTrainingCreateResponseVM {

    private Integer examPaperId;

    public SmartTrainingCreateResponseVM(Integer examPaperId) {
        this.examPaperId = examPaperId;
    }

    public Integer getExamPaperId() {
        return examPaperId;
    }

    public void setExamPaperId(Integer examPaperId) {
        this.examPaperId = examPaperId;
    }
}
