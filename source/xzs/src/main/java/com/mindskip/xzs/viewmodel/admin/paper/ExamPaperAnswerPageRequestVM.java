package com.mindskip.xzs.viewmodel.admin.paper;

import com.mindskip.xzs.base.BasePage;

import java.util.List;

public class ExamPaperAnswerPageRequestVM extends BasePage {
    private Integer subjectId;
    private Integer classId;
    private List<Integer> classIds;

    public Integer getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(Integer subjectId) {
        this.subjectId = subjectId;
    }

    public Integer getClassId() {
        return classId;
    }

    public void setClassId(Integer classId) {
        this.classId = classId;
    }

    public List<Integer> getClassIds() {
        return classIds;
    }

    public void setClassIds(List<Integer> classIds) {
        this.classIds = classIds;
    }
}
