package com.mindskip.xzs.viewmodel.admin.practice;

import java.util.Date;
import java.util.List;

public class PracticeObservationRequestVM {

    private Integer days;
    private String studentName;
    private Integer classId;
    private List<Integer> classIds;
    private Date previousStartTime;
    private Date currentStartTime;
    private Date endTime;

    public Integer getDays() {
        return days;
    }

    public void setDays(Integer days) {
        this.days = days;
    }

    public String getStudentName() {
        return studentName;
    }

    public void setStudentName(String studentName) {
        this.studentName = studentName;
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

    public Date getPreviousStartTime() {
        return previousStartTime;
    }

    public void setPreviousStartTime(Date previousStartTime) {
        this.previousStartTime = previousStartTime;
    }

    public Date getCurrentStartTime() {
        return currentStartTime;
    }

    public void setCurrentStartTime(Date currentStartTime) {
        this.currentStartTime = currentStartTime;
    }

    public Date getEndTime() {
        return endTime;
    }

    public void setEndTime(Date endTime) {
        this.endTime = endTime;
    }
}
