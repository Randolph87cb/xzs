package com.mindskip.xzs.service;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.viewmodel.admin.clazz.ClassPageRequestVM;

import java.util.List;

public interface SchoolClassService extends BaseService<SchoolClass> {

    PageInfo<SchoolClass> page(ClassPageRequestVM requestVM);

    List<SchoolClass> selectOptions(ClassPageRequestVM requestVM);

    List<Integer> selectIdsByTeacherId(Integer teacherId);
}
