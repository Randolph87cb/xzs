package com.mindskip.xzs.repository;

import com.mindskip.xzs.domain.other.KeyValue;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.viewmodel.admin.question.QuestionPageRequestVM;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.Date;
import java.util.List;

@Mapper
public interface QuestionMapper extends BaseMapper<Question> {

    List<Question> page(QuestionPageRequestVM requestVM);

    List<Question> selectByIds(@Param("ids") List<Integer> ids);

    List<Question> selectRandomBySubjectId(@Param("subjectId") Integer subjectId, @Param("limit") Integer limit);

    List<Question> selectRandomBySubjectIdAndKnowledgePoint(@Param("subjectId") Integer subjectId,
                                                            @Param("knowledgePoint") String knowledgePoint,
                                                            @Param("limit") Integer limit);

    Integer selectCountBySubjectIdAndKnowledgePoint(@Param("subjectId") Integer subjectId,
                                                    @Param("knowledgePoint") String knowledgePoint);

    List<String> selectKnowledgePointsBySubjectId(@Param("subjectId") Integer subjectId);

    Integer selectAllCount();

    List<KeyValue> selectCountByDate(@Param("startTime") Date startTime,@Param("endTime") Date endTime);
}
