package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.viewmodel.admin.clazz.ClassEditRequestVM;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.Assert.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class ClassControllerTest {

    private SchoolClassService schoolClassService;
    private ClassScopeService classScopeService;
    private UserService userService;
    private WebContext webContext;
    private ClassController controller;

    @Before
    public void setUp() {
        schoolClassService = mock(SchoolClassService.class);
        classScopeService = mock(ClassScopeService.class);
        userService = mock(UserService.class);
        webContext = mock(WebContext.class);
        controller = new ClassController(schoolClassService, classScopeService, userService);
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void editAllowsAdminAsClassTeacherWhenCurrentUserIsAdmin() {
        when(webContext.getCurrentUser()).thenReturn(user(12, RoleEnum.ADMIN));
        when(userService.getUserById(33)).thenReturn(user(33, RoleEnum.ADMIN));
        when(classScopeService.canBeClassTeacher(any())).thenReturn(true);

        RestResponse<SchoolClass> response = controller.edit(classRequest(33));

        assertEquals(1, response.getCode());
        ArgumentCaptor<SchoolClass> captor = ArgumentCaptor.forClass(SchoolClass.class);
        verify(schoolClassService).insertByFilter(captor.capture());
        assertEquals(Integer.valueOf(33), captor.getValue().getTeacherId());
    }

    @Test
    public void editForTeacherKeepsCurrentTeacherAsClassTeacher() {
        User currentTeacher = user(44, RoleEnum.TEACHER);
        when(webContext.getCurrentUser()).thenReturn(currentTeacher);
        when(classScopeService.isTeacher(currentTeacher)).thenReturn(true);
        when(userService.getUserById(44)).thenReturn(currentTeacher);
        when(classScopeService.canBeClassTeacher(currentTeacher)).thenReturn(true);

        RestResponse<SchoolClass> response = controller.edit(classRequest(33));

        assertEquals(1, response.getCode());
        ArgumentCaptor<SchoolClass> captor = ArgumentCaptor.forClass(SchoolClass.class);
        verify(schoolClassService).insertByFilter(captor.capture());
        assertEquals(Integer.valueOf(44), captor.getValue().getTeacherId());
    }

    private ClassEditRequestVM classRequest(Integer teacherId) {
        ClassEditRequestVM request = new ClassEditRequestVM();
        request.setName("GESP");
        request.setGradeLevel(4);
        request.setTeacherId(teacherId);
        return request;
    }

    private User user(Integer id, RoleEnum role) {
        User user = new User();
        user.setId(id);
        user.setRole(role.getCode());
        return user;
    }
}
