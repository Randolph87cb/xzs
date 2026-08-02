package com.mindskip.xzs.domain.exam;

import java.util.List;

public class ExamPaperItemObject {
    public static final String QUESTION = "QUESTION";
    public static final String QUESTION_GROUP = "QUESTION_GROUP";

    private String type;
    private Integer id;
    private Integer itemOrder;
    private List<ExamPaperQuestionItemObject> questionItems;

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public Integer getId() { return id; }
    public void setId(Integer id) { this.id = id; }
    public Integer getItemOrder() { return itemOrder; }
    public void setItemOrder(Integer itemOrder) { this.itemOrder = itemOrder; }
    public List<ExamPaperQuestionItemObject> getQuestionItems() { return questionItems; }
    public void setQuestionItems(List<ExamPaperQuestionItemObject> questionItems) { this.questionItems = questionItems; }
}
