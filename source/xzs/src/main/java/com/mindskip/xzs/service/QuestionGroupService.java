package com.mindskip.xzs.service;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.domain.QuestionGroup;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupResponseVM;

import java.util.List;

public interface QuestionGroupService extends BaseService<QuestionGroup> {
    PageInfo<QuestionGroupResponseVM> page(QuestionGroupPageRequestVM requestVM);
    QuestionGroup save(QuestionGroupEditRequestVM model, Integer userId);
    QuestionGroupResponseVM selectFullById(Integer id);
    List<QuestionGroup> selectActiveBySubjectId(Integer subjectId);
    void softDelete(Integer id);
}
