package com.mindskip.xzs.viewmodel.admin.question;

import java.util.List;

public class QuestionImportResultVM {

    private Integer totalCount;

    private Integer successCount;

    private List<Integer> questionIds;

    public QuestionImportResultVM(Integer totalCount, Integer successCount, List<Integer> questionIds) {
        this.totalCount = totalCount;
        this.successCount = successCount;
        this.questionIds = questionIds;
    }

    public Integer getTotalCount() {
        return totalCount;
    }

    public void setTotalCount(Integer totalCount) {
        this.totalCount = totalCount;
    }

    public Integer getSuccessCount() {
        return successCount;
    }

    public void setSuccessCount(Integer successCount) {
        this.successCount = successCount;
    }

    public List<Integer> getQuestionIds() {
        return questionIds;
    }

    public void setQuestionIds(List<Integer> questionIds) {
        this.questionIds = questionIds;
    }
}
