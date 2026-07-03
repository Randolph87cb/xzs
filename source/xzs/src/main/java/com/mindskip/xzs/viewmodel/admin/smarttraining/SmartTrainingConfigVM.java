package com.mindskip.xzs.viewmodel.admin.smarttraining;

import javax.validation.Valid;
import javax.validation.constraints.Min;
import javax.validation.constraints.NotEmpty;
import javax.validation.constraints.NotNull;
import java.util.List;

public class SmartTrainingConfigVM {

    private Integer id;

    @NotNull
    private Integer subjectId;

    @NotNull
    @Min(1)
    private Integer questionCount;

    @Valid
    @NotEmpty
    private List<SmartTrainingRuleVM> rules;

    public Integer getId() {
        return id;
    }

    public void setId(Integer id) {
        this.id = id;
    }

    public Integer getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(Integer subjectId) {
        this.subjectId = subjectId;
    }

    public Integer getQuestionCount() {
        return questionCount;
    }

    public void setQuestionCount(Integer questionCount) {
        this.questionCount = questionCount;
    }

    public List<SmartTrainingRuleVM> getRules() {
        return rules;
    }

    public void setRules(List<SmartTrainingRuleVM> rules) {
        this.rules = rules;
    }
}
