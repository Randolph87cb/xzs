package com.mindskip.xzs.viewmodel.admin.exam;

import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;


import javax.validation.Valid;
import javax.validation.constraints.NotBlank;
import javax.validation.constraints.Size;
import java.util.List;


public class ExamPaperTitleItemVM {

    @NotBlank(message = "标题内容不能为空")
    private String name;

    @Size(min = 1,message = "请添加题目")
    @Valid
    private List<QuestionEditRequestVM> questionItems;

    @Valid
    private List<ExamPaperItemVM> paperItems;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public List<QuestionEditRequestVM> getQuestionItems() {
        return questionItems;
    }

    public void setQuestionItems(List<QuestionEditRequestVM> questionItems) {
        this.questionItems = questionItems;
    }

    public List<ExamPaperItemVM> getPaperItems() { return paperItems; }
    public void setPaperItems(List<ExamPaperItemVM> paperItems) { this.paperItems = paperItems; }
}
