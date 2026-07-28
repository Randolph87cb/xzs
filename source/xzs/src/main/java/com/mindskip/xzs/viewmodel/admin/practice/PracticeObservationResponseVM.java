package com.mindskip.xzs.viewmodel.admin.practice;

import java.util.ArrayList;
import java.util.List;

public class PracticeObservationResponseVM {

    private String periodStart;
    private String periodEnd;
    private List<String> dates = new ArrayList<>();
    private Summary summary = new Summary();
    private List<Student> students = new ArrayList<>();
    private String improvementRule;

    public String getPeriodStart() {
        return periodStart;
    }

    public void setPeriodStart(String periodStart) {
        this.periodStart = periodStart;
    }

    public String getPeriodEnd() {
        return periodEnd;
    }

    public void setPeriodEnd(String periodEnd) {
        this.periodEnd = periodEnd;
    }

    public List<String> getDates() {
        return dates;
    }

    public void setDates(List<String> dates) {
        this.dates = dates;
    }

    public Summary getSummary() {
        return summary;
    }

    public void setSummary(Summary summary) {
        this.summary = summary;
    }

    public List<Student> getStudents() {
        return students;
    }

    public void setStudents(List<Student> students) {
        this.students = students;
    }

    public String getImprovementRule() {
        return improvementRule;
    }

    public void setImprovementRule(String improvementRule) {
        this.improvementRule = improvementRule;
    }

    public static class Summary {
        private Integer activeStudentCount = 0;
        private Integer totalQuestionCount = 0;
        private Double weightedAccuracy;
        private Integer improvedStudentCount = 0;

        public Integer getActiveStudentCount() {
            return activeStudentCount;
        }

        public void setActiveStudentCount(Integer activeStudentCount) {
            this.activeStudentCount = activeStudentCount;
        }

        public Integer getTotalQuestionCount() {
            return totalQuestionCount;
        }

        public void setTotalQuestionCount(Integer totalQuestionCount) {
            this.totalQuestionCount = totalQuestionCount;
        }

        public Double getWeightedAccuracy() {
            return weightedAccuracy;
        }

        public void setWeightedAccuracy(Double weightedAccuracy) {
            this.weightedAccuracy = weightedAccuracy;
        }

        public Integer getImprovedStudentCount() {
            return improvedStudentCount;
        }

        public void setImprovedStudentCount(Integer improvedStudentCount) {
            this.improvedStudentCount = improvedStudentCount;
        }
    }

    public static class Student {
        private Integer id;
        private String userName;
        private String name;
        private String imagePath;
        private Integer classId;
        private String className;
        private Integer gradeLevel;
        private String directionLabel;
        private Integer questionCount = 0;
        private Integer correctCount = 0;
        private Double weightedAccuracy;
        private Boolean improved;
        private String attentionText;
        private List<Day> days = new ArrayList<>();
        private List<Practice> recentPractices = new ArrayList<>();
        private Boolean weakPointsSupported = false;
        private String weakPointsMessage = "当前答卷汇总数据未保存可靠的知识点维度，暂不展示薄弱知识点。";

        public Integer getId() {
            return id;
        }

        public void setId(Integer id) {
            this.id = id;
        }

        public String getUserName() {
            return userName;
        }

        public void setUserName(String userName) {
            this.userName = userName;
        }

        public String getName() {
            return name;
        }

        public void setName(String name) {
            this.name = name;
        }

        public String getImagePath() {
            return imagePath;
        }

        public void setImagePath(String imagePath) {
            this.imagePath = imagePath;
        }

        public Integer getClassId() {
            return classId;
        }

        public void setClassId(Integer classId) {
            this.classId = classId;
        }

        public String getClassName() {
            return className;
        }

        public void setClassName(String className) {
            this.className = className;
        }

        public Integer getGradeLevel() {
            return gradeLevel;
        }

        public void setGradeLevel(Integer gradeLevel) {
            this.gradeLevel = gradeLevel;
        }

        public String getDirectionLabel() {
            return directionLabel;
        }

        public void setDirectionLabel(String directionLabel) {
            this.directionLabel = directionLabel;
        }

        public Integer getQuestionCount() {
            return questionCount;
        }

        public void setQuestionCount(Integer questionCount) {
            this.questionCount = questionCount;
        }

        public Integer getCorrectCount() {
            return correctCount;
        }

        public void setCorrectCount(Integer correctCount) {
            this.correctCount = correctCount;
        }

        public Double getWeightedAccuracy() {
            return weightedAccuracy;
        }

        public void setWeightedAccuracy(Double weightedAccuracy) {
            this.weightedAccuracy = weightedAccuracy;
        }

        public Boolean getImproved() {
            return improved;
        }

        public void setImproved(Boolean improved) {
            this.improved = improved;
        }

        public String getAttentionText() {
            return attentionText;
        }

        public void setAttentionText(String attentionText) {
            this.attentionText = attentionText;
        }

        public List<Day> getDays() {
            return days;
        }

        public void setDays(List<Day> days) {
            this.days = days;
        }

        public List<Practice> getRecentPractices() {
            return recentPractices;
        }

        public void setRecentPractices(List<Practice> recentPractices) {
            this.recentPractices = recentPractices;
        }

        public Boolean getWeakPointsSupported() {
            return weakPointsSupported;
        }

        public void setWeakPointsSupported(Boolean weakPointsSupported) {
            this.weakPointsSupported = weakPointsSupported;
        }

        public String getWeakPointsMessage() {
            return weakPointsMessage;
        }

        public void setWeakPointsMessage(String weakPointsMessage) {
            this.weakPointsMessage = weakPointsMessage;
        }
    }

    public static class Day {
        private String date;
        private Integer questionCount = 0;
        private Integer correctCount = 0;
        private Double weightedAccuracy;

        public Day(String date) {
            this.date = date;
        }

        public String getDate() {
            return date;
        }

        public void setDate(String date) {
            this.date = date;
        }

        public Integer getQuestionCount() {
            return questionCount;
        }

        public void setQuestionCount(Integer questionCount) {
            this.questionCount = questionCount;
        }

        public Integer getCorrectCount() {
            return correctCount;
        }

        public void setCorrectCount(Integer correctCount) {
            this.correctCount = correctCount;
        }

        public Double getWeightedAccuracy() {
            return weightedAccuracy;
        }

        public void setWeightedAccuracy(Double weightedAccuracy) {
            this.weightedAccuracy = weightedAccuracy;
        }
    }

    public static class Practice {
        private Integer id;
        private String paperName;
        private String createTime;
        private Integer questionCount;
        private Integer correctCount;
        private Double weightedAccuracy;

        public Integer getId() {
            return id;
        }

        public void setId(Integer id) {
            this.id = id;
        }

        public String getPaperName() {
            return paperName;
        }

        public void setPaperName(String paperName) {
            this.paperName = paperName;
        }

        public String getCreateTime() {
            return createTime;
        }

        public void setCreateTime(String createTime) {
            this.createTime = createTime;
        }

        public Integer getQuestionCount() {
            return questionCount;
        }

        public void setQuestionCount(Integer questionCount) {
            this.questionCount = questionCount;
        }

        public Integer getCorrectCount() {
            return correctCount;
        }

        public void setCorrectCount(Integer correctCount) {
            this.correctCount = correctCount;
        }

        public Double getWeightedAccuracy() {
            return weightedAccuracy;
        }

        public void setWeightedAccuracy(Double weightedAccuracy) {
            this.weightedAccuracy = weightedAccuracy;
        }
    }
}
