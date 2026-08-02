package com.mindskip.xzs.repository;

import com.mindskip.xzs.domain.QuestionGroup;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupPageRequestVM;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;

@Mapper
public interface QuestionGroupMapper extends BaseMapper<QuestionGroup> {
    List<QuestionGroup> page(QuestionGroupPageRequestVM requestVM);
    List<QuestionGroup> selectActiveBySubjectId(@Param("subjectId") Integer subjectId);
    List<QuestionGroup> selectByIds(@Param("ids") List<Integer> ids);
}
