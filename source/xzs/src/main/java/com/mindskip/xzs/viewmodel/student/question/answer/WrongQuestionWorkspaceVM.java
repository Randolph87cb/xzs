package com.mindskip.xzs.viewmodel.student.question.answer;

import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperSubmitItemVM;
import com.mindskip.xzs.viewmodel.student.question.correction.QuestionCorrectionRecordVM;

import java.util.List;

public class WrongQuestionWorkspaceVM {

    private QuestionEditRequestVM questionVM;
    private ExamPaperSubmitItemVM questionAnswerVM;
    private QuestionCorrectionRecordVM correction;
    private List<QuestionWrongHistoryVM> wrongHistory;

    public QuestionEditRequestVM getQuestionVM() {
        return questionVM;
    }

    public void setQuestionVM(QuestionEditRequestVM questionVM) {
        this.questionVM = questionVM;
    }

    public ExamPaperSubmitItemVM getQuestionAnswerVM() {
        return questionAnswerVM;
    }

    public void setQuestionAnswerVM(ExamPaperSubmitItemVM questionAnswerVM) {
        this.questionAnswerVM = questionAnswerVM;
    }

    public QuestionCorrectionRecordVM getCorrection() {
        return correction;
    }

    public void setCorrection(QuestionCorrectionRecordVM correction) {
        this.correction = correction;
    }

    public List<QuestionWrongHistoryVM> getWrongHistory() {
        return wrongHistory;
    }

    public void setWrongHistory(List<QuestionWrongHistoryVM> wrongHistory) {
        this.wrongHistory = wrongHistory;
    }
}
