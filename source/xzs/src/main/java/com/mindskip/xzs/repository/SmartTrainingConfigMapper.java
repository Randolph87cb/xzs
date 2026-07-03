package com.mindskip.xzs.repository;

import com.mindskip.xzs.domain.SmartTrainingConfig;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;

@Mapper
public interface SmartTrainingConfigMapper extends BaseMapper<SmartTrainingConfig> {

    SmartTrainingConfig selectBySubjectId(@Param("subjectId") Integer subjectId);

    List<SmartTrainingConfig> selectAll();
}
