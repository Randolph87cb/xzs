package com.mindskip.xzs.viewmodel.admin.smarttraining;

import javax.validation.constraints.Min;
import javax.validation.constraints.NotBlank;

public class SmartTrainingRuleVM {

    @NotBlank
    private String knowledgePoint;

    @Min(1)
    private Integer questionCount;

    @Min(0)
    private Integer minCount;

    @Min(0)
    private Integer maxCount;

    @Min(1)
    private Integer weight;

    private Boolean enabled;

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

    public Integer getMinCount() {
        return minCount;
    }

    public void setMinCount(Integer minCount) {
        this.minCount = minCount;
    }

    public Integer getMaxCount() {
        return maxCount;
    }

    public void setMaxCount(Integer maxCount) {
        this.maxCount = maxCount;
    }

    public Integer getWeight() {
        return weight;
    }

    public void setWeight(Integer weight) {
        this.weight = weight;
    }

    public Boolean getEnabled() {
        return enabled;
    }

    public void setEnabled(Boolean enabled) {
        this.enabled = enabled;
    }
}
