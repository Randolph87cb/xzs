package com.mindskip.xzs.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.configuration.spring.security.AuthenticationBean;
import com.mindskip.xzs.configuration.spring.security.WebAuthCookie;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.UserToken;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.domain.enums.UserStatusEnum;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.service.UserTokenService;
import com.mindskip.xzs.viewmodel.student.user.UserResponseVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.Map;
import java.util.UUID;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class WebAuthControllerTest {

    private AuthenticationService authenticationService;
    private UserService userService;
    private UserTokenService userTokenService;
    private SchoolClassService schoolClassService;
    private WebAuthController controller;

    @Before
    public void setUp() {
        authenticationService = mock(AuthenticationService.class);
        userService = mock(UserService.class);
        userTokenService = mock(UserTokenService.class);
        schoolClassService = mock(SchoolClassService.class);
        controller = new WebAuthController(authenticationService, userService, userTokenService, schoolClassService, mock(ApplicationEventPublisher.class));
    }

    @Test
    public void adminLoginAllowsTeacherAccount() {
        String token = UUID.randomUUID().toString();
        User teacher = user("teacher", RoleEnum.TEACHER);
        UserToken userToken = new UserToken();
        userToken.setToken(token);
        userToken.setUserName(teacher.getUserName());

        when(userService.getUserByUserName("teacher")).thenReturn(teacher);
        when(authenticationService.authUser(teacher, "teacher", "pwd")).thenReturn(true);
        when(userTokenService.insertWebUserToken(teacher)).thenReturn(userToken);

        AuthenticationBean model = new AuthenticationBean();
        model.setUserName("teacher");
        model.setPassword("pwd");

        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();
        RestResponse<User> result = controller.adminLogin(model, request, response);

        assertEquals(1, result.getCode());
        assertEquals("teacher", result.getResponse().getUserName());
        assertNull(result.getResponse().getPassword());
        assertNull(result.getResponse().getId());
        assertTrue(response.getHeader("Set-Cookie").contains(WebAuthCookie.ADMIN_COOKIE_NAME + "=" + token));
    }

    @Test
    public void studentLoginReturnsCompleteWhitelistedProfileWithClassName() {
        String token = UUID.randomUUID().toString();
        User student = user("student", RoleEnum.STUDENT);
        student.setNickName("nick");
        student.setRealName("Real Student");
        student.setClassId(7);
        student.setUserLevel(3);
        student.setImagePath("/image.png");
        UserToken userToken = new UserToken();
        userToken.setToken(token);
        userToken.setUserName(student.getUserName());
        SchoolClass schoolClass = new SchoolClass();
        schoolClass.setId(7);
        schoolClass.setName("Class 7");

        when(userService.getUserByUserName("student")).thenReturn(student);
        when(authenticationService.authUser(student, "student", "pwd")).thenReturn(true);
        when(userTokenService.insertWebUserToken(student)).thenReturn(userToken);
        when(schoolClassService.selectById(7)).thenReturn(schoolClass);

        AuthenticationBean model = new AuthenticationBean();
        model.setUserName("student");
        model.setPassword("pwd");
        RestResponse<UserResponseVM> result = controller.studentLogin(
                model, new MockHttpServletRequest(), new MockHttpServletResponse());

        assertEquals(1, result.getCode());
        assertEquals(Integer.valueOf(1), result.getResponse().getId());
        assertEquals("student", result.getResponse().getUserName());
        assertEquals("nick", result.getResponse().getNickName());
        assertEquals("Real Student", result.getResponse().getRealName());
        assertEquals(Integer.valueOf(7), result.getResponse().getClassId());
        assertEquals("Class 7", result.getResponse().getClassName());
        assertEquals(Integer.valueOf(3), result.getResponse().getUserLevel());
        Map<String, Object> serialized = new ObjectMapper().convertValue(result.getResponse(), Map.class);
        assertFalse(serialized.containsKey("password"));
        assertFalse(serialized.containsKey("token"));
    }

    @Test
    public void studentLoginRejectsTeacherAccount() {
        User teacher = user("teacher", RoleEnum.TEACHER);
        when(userService.getUserByUserName("teacher")).thenReturn(teacher);
        when(authenticationService.authUser(teacher, "teacher", "pwd")).thenReturn(true);

        AuthenticationBean model = new AuthenticationBean();
        model.setUserName("teacher");
        model.setPassword("pwd");

        RestResponse<UserResponseVM> result = controller.studentLogin(model, new MockHttpServletRequest(), new MockHttpServletResponse());

        assertEquals(502, result.getCode());
        assertEquals("账号类型不匹配", result.getMessage());
    }

    private User user(String userName, RoleEnum role) {
        User user = new User();
        user.setId(1);
        user.setUserName(userName);
        user.setPassword("pwd");
        user.setRole(role.getCode());
        user.setStatus(UserStatusEnum.Enable.getCode());
        user.setDeleted(false);
        return user;
    }
}
