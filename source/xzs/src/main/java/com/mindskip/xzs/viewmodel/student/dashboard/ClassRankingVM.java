package com.mindskip.xzs.viewmodel.student.dashboard;

import com.mindskip.xzs.domain.other.ClassRankingItem;
import com.mindskip.xzs.utility.DateTimeUtil;

import java.math.BigDecimal;

public class ClassRankingVM {

    private Integer userId;
    private String userName;
    private String realName;
    private String nickName;
    private Integer rank;
    private Integer paperCount;
    private Integer questionCount;
    private Integer correctCount;
    private BigDecimal accuracyRate;
    private Integer correctionCount;
    private Integer resubmitCount;
    private String lastSubmitTime;
    private BigDecimal score;

    public static ClassRankingVM from(ClassRankingItem item) {
        ClassRankingVM vm = new ClassRankingVM();
        vm.setUserId(item.getUserId());
        vm.setUserName(item.getUserName());
        vm.setRealName(item.getRealName());
        vm.setNickName(item.getNickName());
        vm.setRank(item.getRank());
        vm.setPaperCount(item.getPaperCount());
        vm.setQuestionCount(item.getQuestionCount());
        vm.setCorrectCount(item.getCorrectCount());
        vm.setAccuracyRate(item.getAccuracyRate());
        vm.setCorrectionCount(item.getCorrectionCount());
        vm.setResubmitCount(item.getResubmitCount());
        vm.setLastSubmitTime(DateTimeUtil.dateFormat(item.getLastSubmitTime()));
        vm.setScore(item.getScore());
        return vm;
    }

    public Integer getUserId() {
        return userId;
    }

    public void setUserId(Integer userId) {
        this.userId = userId;
    }

    public String getUserName() {
        return userName;
    }

    public void setUserName(String userName) {
        this.userName = userName;
    }

    public String getRealName() {
        return realName;
    }

    public void setRealName(String realName) {
        this.realName = realName;
    }

    public String getNickName() {
        return nickName;
    }

    public void setNickName(String nickName) {
        this.nickName = nickName;
    }

    public Integer getRank() {
        return rank;
    }

    public void setRank(Integer rank) {
        this.rank = rank;
    }

    public Integer getPaperCount() {
        return paperCount;
    }

    public void setPaperCount(Integer paperCount) {
        this.paperCount = paperCount;
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

    public BigDecimal getAccuracyRate() {
        return accuracyRate;
    }

    public void setAccuracyRate(BigDecimal accuracyRate) {
        this.accuracyRate = accuracyRate;
    }

    public Integer getCorrectionCount() {
        return correctionCount;
    }

    public void setCorrectionCount(Integer correctionCount) {
        this.correctionCount = correctionCount;
    }

    public Integer getResubmitCount() {
        return resubmitCount;
    }

    public void setResubmitCount(Integer resubmitCount) {
        this.resubmitCount = resubmitCount;
    }

    public String getLastSubmitTime() {
        return lastSubmitTime;
    }

    public void setLastSubmitTime(String lastSubmitTime) {
        this.lastSubmitTime = lastSubmitTime;
    }

    public BigDecimal getScore() {
        return score;
    }

    public void setScore(BigDecimal score) {
        this.score = score;
    }
}
