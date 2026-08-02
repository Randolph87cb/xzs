package com.mindskip.xzs.domain.exam;


import java.util.List;

public class ExamPaperTitleItemObject {

    private String name;

    private List<ExamPaperQuestionItemObject> questionItems;

    private List<ExamPaperItemObject> paperItems;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public List<ExamPaperQuestionItemObject> getQuestionItems() {
        return questionItems;
    }

    public void setQuestionItems(List<ExamPaperQuestionItemObject> questionItems) {
        this.questionItems = questionItems;
    }

    public List<ExamPaperItemObject> getPaperItems() { return paperItems; }
    public void setPaperItems(List<ExamPaperItemObject> paperItems) { this.paperItems = paperItems; }
}
