package com.mindskip.xzs.repository;

import com.mindskip.xzs.domain.TaskExam;
import com.mindskip.xzs.viewmodel.admin.task.TaskPageRequestVM;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;

@Mapper
public interface TaskExamMapper extends BaseMapper<TaskExam> {

    List<TaskExam> page(TaskPageRequestVM requestVM);

    List<TaskExam> getByGradeLevel(@Param("gradeLevel") Integer gradeLevel);

    List<TaskExam> getByGradeLevelOrClass(@Param("gradeLevel") Integer gradeLevel, @Param("classId") Integer classId);
}
