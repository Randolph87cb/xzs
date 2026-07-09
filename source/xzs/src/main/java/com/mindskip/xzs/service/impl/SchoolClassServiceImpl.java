package com.mindskip.xzs.service.impl;

import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.repository.SchoolClassMapper;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.viewmodel.admin.clazz.ClassPageRequestVM;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class SchoolClassServiceImpl extends BaseServiceImpl<SchoolClass> implements SchoolClassService {

    private final SchoolClassMapper schoolClassMapper;

    @Autowired
    public SchoolClassServiceImpl(SchoolClassMapper schoolClassMapper) {
        super(schoolClassMapper);
        this.schoolClassMapper = schoolClassMapper;
    }

    @Override
    public PageInfo<SchoolClass> page(ClassPageRequestVM requestVM) {
        return PageHelper.startPage(requestVM.getPageIndex(), requestVM.getPageSize(), "id desc").doSelectPageInfo(() ->
                schoolClassMapper.page(requestVM));
    }

    @Override
    public List<SchoolClass> selectOptions(ClassPageRequestVM requestVM) {
        return schoolClassMapper.selectOptions(requestVM);
    }

    @Override
    public List<Integer> selectIdsByTeacherId(Integer teacherId) {
        return schoolClassMapper.selectIdsByTeacherId(teacherId);
    }
}
