package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.domain.enums.UserStatusEnum;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.UserEventLogService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.viewmodel.admin.user.UserCreateVM;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class UserControllerTest {

    private UserService userService;
    private AuthenticationService authenticationService;
    private UserController controller;

    @Before
    public void setUp() {
        userService = mock(UserService.class);
        authenticationService = mock(AuthenticationService.class);
        controller = new UserController(
                userService,
                mock(UserEventLogService.class),
                authenticationService,
                mock(ClassScopeService.class),
                mock(SubjectService.class));

        WebContext webContext = mock(WebContext.class);
        when(webContext.getCurrentUser()).thenReturn(user(2, "admin", RoleEnum.ADMIN, "admin-password"));
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void editExistingUserWithBlankPasswordDoesNotOverwritePassword() {
        User before = user(2, "admin", RoleEnum.ADMIN, "original-hash");
        when(userService.getUserById(2)).thenReturn(before);

        UserCreateVM model = new UserCreateVM();
        model.setId(2);
        model.setUserName("admin");
        model.setRealName("Administrator");
        model.setNickName("Admin Nick");
        model.setPassword("   ");
        model.setRole(RoleEnum.ADMIN.getCode());
        model.setStatus(UserStatusEnum.Enable.getCode());

        RestResponse<User> response = controller.edit(model);

        assertEquals(1, response.getCode());
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userService).updateByIdFilter(captor.capture());
        assertNull(captor.getValue().getPassword());
        assertEquals("Admin Nick", captor.getValue().getNickName());
        verify(authenticationService, never()).pwdEncode(any());
    }

    @Test
    public void createUserAcceptsChineseLoginNameAndNormalizesWhitespace() {
        when(userService.getUserByUserName("彬彬老师")).thenReturn(null);
        when(authenticationService.pwdEncode("pwd")).thenReturn("encoded-pwd");

        UserCreateVM model = new UserCreateVM();
        model.setUserName("  彬彬老师  ");
        model.setRealName("  彬彬老师  ");
        model.setPassword(" pwd ");
        model.setRole(RoleEnum.TEACHER.getCode());
        model.setStatus(UserStatusEnum.Enable.getCode());

        RestResponse<User> response = controller.edit(model);

        assertEquals(1, response.getCode());
        verify(userService).getUserByUserName("彬彬老师");
        verify(authenticationService).pwdEncode("pwd");
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userService).insertByFilter(captor.capture());
        assertEquals("彬彬老师", captor.getValue().getUserName());
        assertEquals("彬彬老师", captor.getValue().getRealName());
        assertEquals("encoded-pwd", captor.getValue().getPassword());
        assertEquals(Integer.valueOf(RoleEnum.TEACHER.getCode()), captor.getValue().getRole());
    }

    private User user(Integer id, String userName, RoleEnum role, String password) {
        User user = new User();
        user.setId(id);
        user.setUserName(userName);
        user.setRealName(userName);
        user.setPassword(password);
        user.setRole(role.getCode());
        user.setStatus(UserStatusEnum.Enable.getCode());
        user.setDeleted(false);
        return user;
    }
}
