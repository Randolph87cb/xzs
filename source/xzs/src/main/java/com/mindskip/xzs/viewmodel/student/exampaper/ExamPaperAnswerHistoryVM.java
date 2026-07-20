package com.mindskip.xzs.viewmodel.student.exampaper;

import java.util.ArrayList;
import java.util.List;

public class ExamPaperAnswerHistoryVM {

    private Integer examPaperId;

    private Integer attemptCount;

    private String bestScore;

    private String latestScore;

    private String averageScore;

    private List<ExamPaperAnswerHistoryItemVM> items = new ArrayList<>();

    public Integer getExamPaperId() {
        return examPaperId;
    }

    public void setExamPaperId(Integer examPaperId) {
        this.examPaperId = examPaperId;
    }

    public Integer getAttemptCount() {
        return attemptCount;
    }

    public void setAttemptCount(Integer attemptCount) {
        this.attemptCount = attemptCount;
    }

    public String getBestScore() {
        return bestScore;
    }

    public void setBestScore(String bestScore) {
        this.bestScore = bestScore;
    }

    public String getLatestScore() {
        return latestScore;
    }

    public void setLatestScore(String latestScore) {
        this.latestScore = latestScore;
    }

    public String getAverageScore() {
        return averageScore;
    }

    public void setAverageScore(String averageScore) {
        this.averageScore = averageScore;
    }

    public List<ExamPaperAnswerHistoryItemVM> getItems() {
        return items;
    }

    public void setItems(List<ExamPaperAnswerHistoryItemVM> items) {
        this.items = items;
    }
}
