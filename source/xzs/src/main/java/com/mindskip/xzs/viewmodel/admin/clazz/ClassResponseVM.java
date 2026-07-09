package com.mindskip.xzs.viewmodel.admin.clazz;

import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.viewmodel.BaseVM;

public class ClassResponseVM extends BaseVM {

    private Integer id;
    private String name;
    private Integer gradeLevel;
    private Integer teacherId;
    private String teacherName;
    private Integer status;
    private String createTime;
    private String modifyTime;

    public static ClassResponseVM from(SchoolClass schoolClass) {
        ClassResponseVM vm = modelMapper.map(schoolClass, ClassResponseVM.class);
        vm.setCreateTime(DateTimeUtil.dateFormat(schoolClass.getCreateTime()));
        vm.setModifyTime(DateTimeUtil.dateFormat(schoolClass.getModifyTime()));
        return vm;
    }

    public Integer getId() {
        return id;
    }

    public void setId(Integer id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public Integer getGradeLevel() {
        return gradeLevel;
    }

    public void setGradeLevel(Integer gradeLevel) {
        this.gradeLevel = gradeLevel;
    }

    public Integer getTeacherId() {
        return teacherId;
    }

    public void setTeacherId(Integer teacherId) {
        this.teacherId = teacherId;
    }

    public String getTeacherName() {
        return teacherName;
    }

    public void setTeacherName(String teacherName) {
        this.teacherName = teacherName;
    }

    public Integer getStatus() {
        return status;
    }

    public void setStatus(Integer status) {
        this.status = status;
    }

    public String getCreateTime() {
        return createTime;
    }

    public void setCreateTime(String createTime) {
        this.createTime = createTime;
    }

    public String getModifyTime() {
        return modifyTime;
    }

    public void setModifyTime(String modifyTime) {
        this.modifyTime = modifyTime;
    }
}
