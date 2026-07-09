package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.base.SystemCode;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.exception.BusinessException;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.service.UserService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Collections;
import java.util.List;

@Service
public class ClassScopeServiceImpl implements ClassScopeService {

    private final SchoolClassService schoolClassService;
    private final UserService userService;

    @Autowired
    public ClassScopeServiceImpl(SchoolClassService schoolClassService, UserService userService) {
        this.schoolClassService = schoolClassService;
        this.userService = userService;
    }

    @Override
    public boolean isAdmin(User user) {
        return user != null && RoleEnum.ADMIN.getCode() == user.getRole();
    }

    @Override
    public boolean isTeacher(User user) {
        return user != null && RoleEnum.TEACHER.getCode() == user.getRole();
    }

    @Override
    public List<Integer> teacherClassIds(User teacher) {
        if (!isTeacher(teacher)) {
            return Collections.emptyList();
        }
        return schoolClassService.selectIdsByTeacherId(teacher.getId());
    }

    @Override
    public boolean canManageClass(User user, Integer classId) {
        if (isAdmin(user)) {
            return true;
        }
        if (!isTeacher(user) || classId == null) {
            return false;
        }
        SchoolClass schoolClass = schoolClassService.selectById(classId);
        return schoolClass != null && Boolean.FALSE.equals(schoolClass.getDeleted()) && user.getId().equals(schoolClass.getTeacherId());
    }

    @Override
    public boolean canManageStudent(User user, Integer studentId) {
        if (isAdmin(user)) {
            return true;
        }
        if (!isTeacher(user) || studentId == null) {
            return false;
        }
        User student = userService.getUserById(studentId);
        return student != null && RoleEnum.STUDENT.getCode() == student.getRole() && canManageClass(user, student.getClassId());
    }

    @Override
    public void requireClassAccess(User user, Integer classId) {
        if (!canManageClass(user, classId)) {
            throw new BusinessException(SystemCode.AccessDenied.getCode(), "没有该班级的管理权限");
        }
    }

    @Override
    public void requireStudentAccess(User user, Integer studentId) {
        if (!canManageStudent(user, studentId)) {
            throw new BusinessException(SystemCode.AccessDenied.getCode(), "没有该学生的管理权限");
        }
    }
}
