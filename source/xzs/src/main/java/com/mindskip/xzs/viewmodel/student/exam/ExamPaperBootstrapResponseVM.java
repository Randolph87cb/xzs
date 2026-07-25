package com.mindskip.xzs.viewmodel.student.exam;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.viewmodel.student.education.SubjectVM;

import java.util.List;

public class ExamPaperBootstrapResponseVM {

    private List<SubjectVM> subjects;
    private Integer activeSubjectId;
    private PageInfo<ExamPaperPageResponseVM> page;

    public List<SubjectVM> getSubjects() {
        return subjects;
    }

    public void setSubjects(List<SubjectVM> subjects) {
        this.subjects = subjects;
    }

    public Integer getActiveSubjectId() {
        return activeSubjectId;
    }

    public void setActiveSubjectId(Integer activeSubjectId) {
        this.activeSubjectId = activeSubjectId;
    }

    public PageInfo<ExamPaperPageResponseVM> getPage() {
        return page;
    }

    public void setPage(PageInfo<ExamPaperPageResponseVM> page) {
        this.page = page;
    }
}
