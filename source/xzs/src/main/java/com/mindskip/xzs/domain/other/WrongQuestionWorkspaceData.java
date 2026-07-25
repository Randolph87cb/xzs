package com.mindskip.xzs.domain.other;

import com.mindskip.xzs.domain.ExamPaperQuestionCustomerAnswer;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.viewmodel.student.question.correction.QuestionCorrectionRecordVM;

public class WrongQuestionWorkspaceData {

    private ExamPaperQuestionCustomerAnswer customerAnswer;
    private Question question;
    private String questionContent;
    private String answerContent;
    private QuestionCorrectionRecordVM correction;

    public ExamPaperQuestionCustomerAnswer getCustomerAnswer() {
        return customerAnswer;
    }

    public void setCustomerAnswer(ExamPaperQuestionCustomerAnswer customerAnswer) {
        this.customerAnswer = customerAnswer;
    }

    public Question getQuestion() {
        return question;
    }

    public void setQuestion(Question question) {
        this.question = question;
    }

    public String getQuestionContent() {
        return questionContent;
    }

    public void setQuestionContent(String questionContent) {
        this.questionContent = questionContent;
    }

    public String getAnswerContent() {
        return answerContent;
    }

    public void setAnswerContent(String answerContent) {
        this.answerContent = answerContent;
    }

    public QuestionCorrectionRecordVM getCorrection() {
        return correction;
    }

    public void setCorrection(QuestionCorrectionRecordVM correction) {
        this.correction = correction;
    }
}
