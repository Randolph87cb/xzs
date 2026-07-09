package com.mindskip.xzs.service;

import com.mindskip.xzs.domain.User;

import java.util.List;

public interface ClassScopeService {

    boolean isAdmin(User user);

    boolean isTeacher(User user);

    List<Integer> teacherClassIds(User teacher);

    boolean canManageClass(User user, Integer classId);

    boolean canManageStudent(User user, Integer studentId);

    void requireClassAccess(User user, Integer classId);

    void requireStudentAccess(User user, Integer studentId);
}
