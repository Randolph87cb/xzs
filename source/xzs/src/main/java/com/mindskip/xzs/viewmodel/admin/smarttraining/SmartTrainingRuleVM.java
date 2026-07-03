package com.mindskip.xzs.viewmodel.admin.smarttraining;

import javax.validation.constraints.Min;
import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

public class SmartTrainingRuleVM {

    @NotBlank
    private String knowledgePoint;

    @NotNull
    @Min(1)
    private Integer questionCount;

    public String getKnowledgePoint() {
        return knowledgePoint;
    }

    public void setKnowledgePoint(String knowledgePoint) {
        this.knowledgePoint = knowledgePoint;
    }

    public Integer getQuestionCount() {
        return questionCount;
    }

    public void setQuestionCount(Integer questionCount) {
        this.questionCount = questionCount;
    }
}
