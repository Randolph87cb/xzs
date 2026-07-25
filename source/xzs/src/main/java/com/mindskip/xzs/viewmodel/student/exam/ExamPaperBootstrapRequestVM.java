package com.mindskip.xzs.viewmodel.student.exam;

import com.mindskip.xzs.base.BasePage;

import javax.validation.constraints.NotNull;

public class ExamPaperBootstrapRequestVM extends BasePage {

    @NotNull
    private Integer paperType;

    public Integer getPaperType() {
        return paperType;
    }

    public void setPaperType(Integer paperType) {
        this.paperType = paperType;
    }
}
