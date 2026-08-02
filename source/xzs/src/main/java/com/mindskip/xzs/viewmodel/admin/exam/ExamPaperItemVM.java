package com.mindskip.xzs.viewmodel.admin.exam;

import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import java.util.List;

public class ExamPaperItemVM {
    private String type;
    private Integer id;
    private Integer itemOrder;
    private Integer questionGroupType;
    private String questionGroupCode;
    private String title;
    private List<QuestionEditRequestVM> questionItems;

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public Integer getId() { return id; }
    public void setId(Integer id) { this.id = id; }
    public Integer getItemOrder() { return itemOrder; }
    public void setItemOrder(Integer itemOrder) { this.itemOrder = itemOrder; }
    public Integer getQuestionGroupType() { return questionGroupType; }
    public void setQuestionGroupType(Integer questionGroupType) { this.questionGroupType = questionGroupType; }
    public String getQuestionGroupCode() { return questionGroupCode; }
    public void setQuestionGroupCode(String questionGroupCode) { this.questionGroupCode = questionGroupCode; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public List<QuestionEditRequestVM> getQuestionItems() { return questionItems; }
    public void setQuestionItems(List<QuestionEditRequestVM> questionItems) { this.questionItems = questionItems; }
}
