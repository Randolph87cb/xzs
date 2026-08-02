package com.mindskip.xzs.viewmodel.admin.questiongroup;

import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import java.util.List;

public class QuestionGroupResponseVM extends QuestionGroupEditRequestVM {
    private String createTime;
    private Integer questionCount;
    private String totalScore;
    private List<QuestionEditRequestVM> questionItems;

    public String getCreateTime() { return createTime; }
    public void setCreateTime(String createTime) { this.createTime = createTime; }
    public Integer getQuestionCount() { return questionCount; }
    public void setQuestionCount(Integer questionCount) { this.questionCount = questionCount; }
    public String getTotalScore() { return totalScore; }
    public void setTotalScore(String totalScore) { this.totalScore = totalScore; }
    @Override public List<QuestionEditRequestVM> getQuestionItems() { return questionItems; }
    @Override public void setQuestionItems(List<QuestionEditRequestVM> questionItems) { this.questionItems = questionItems; }
}
