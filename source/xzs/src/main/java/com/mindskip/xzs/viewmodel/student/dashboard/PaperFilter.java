package com.mindskip.xzs.viewmodel.student.dashboard;


import java.util.Date;

public class PaperFilter {
    private Integer userId;
    private Date dateTime;
    private Integer examPaperType;
    private Integer gradeLevel;
    private Integer subjectId;

    public Integer getUserId() {
        return userId;
    }

    public void setUserId(Integer userId) {
        this.userId = userId;
    }

    public Date getDateTime() {
        return dateTime;
    }

    public void setDateTime(Date dateTime) {
        this.dateTime = dateTime;
    }

    public Integer getExamPaperType() {
        return examPaperType;
    }

    public void setExamPaperType(Integer examPaperType) {
        this.examPaperType = examPaperType;
    }

    public Integer getGradeLevel() {
        return gradeLevel;
    }

    public void setGradeLevel(Integer gradeLevel) {
        this.gradeLevel = gradeLevel;
    }

    public Integer getSubjectId() {
        return subjectId;
    }

    public void setSubjectId(Integer subjectId) {
        this.subjectId = subjectId;
    }
}
