package com.mindskip.xzs.repository;

import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.viewmodel.admin.clazz.ClassPageRequestVM;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;

@Mapper
public interface SchoolClassMapper extends BaseMapper<SchoolClass> {

    List<SchoolClass> page(ClassPageRequestVM requestVM);

    List<SchoolClass> selectOptions(ClassPageRequestVM requestVM);

    List<Integer> selectIdsByTeacherId(Integer teacherId);
}
