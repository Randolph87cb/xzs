package com.mindskip.xzs.controller.student;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WebContext;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.MessageService;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.service.UserEventLogService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.viewmodel.student.user.StudentChangePasswordVM;
import com.mindskip.xzs.viewmodel.student.user.UserResponseVM;
import com.mindskip.xzs.viewmodel.student.user.UserUpdateVM;
import org.junit.Before;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Date;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class UserControllerTest {

    private UserService userService;
    private AuthenticationService authenticationService;
    private SchoolClassService schoolClassService;
    private WebContext webContext;
    private UserController controller;

    @Before
    public void setUp() {
        userService = mock(UserService.class);
        authenticationService = mock(AuthenticationService.class);
        schoolClassService = mock(SchoolClassService.class);
        controller = new UserController(
                userService,
                mock(UserEventLogService.class),
                mock(MessageService.class),
                authenticationService,
                schoolClassService,
                mock(ApplicationEventPublisher.class));

        webContext = mock(WebContext.class);
        setCurrentUser(user());
        ReflectionTestUtils.setField(controller, "webContext", webContext);
    }

    @Test
    public void updateOnlyPersistsNickNameEvenWhenRequestContainsProfileFields() throws Exception {
        User stored = user();
        when(userService.selectById(7)).thenReturn(stored);

        ObjectMapper objectMapper = new ObjectMapper()
                .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        UserUpdateVM request = objectMapper.readValue("{\"nickName\":\"new nick\",\"realName\":\"hacked\",\"phone\":\"000\",\"age\":\"99\",\"sex\":1,\"birthDay\":\"2000-01-01\",\"userLevel\":9}", UserUpdateVM.class);

        RestResponse response = controller.update(request);

        assertEquals(1, response.getCode());
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userService).updateByIdFilter(captor.capture());
        User update = captor.getValue();
        assertEquals(Integer.valueOf(7), update.getId());
        assertEquals("new nick", update.getNickName());
        assertNull(update.getRealName());
        assertNull(update.getPhone());
        assertNull(update.getAge());
        assertNull(update.getSex());
        assertNull(update.getBirthDay());
        assertNull(update.getUserLevel());
        assertNotNull(update.getModifyTime());
    }

    @Test
    public void currentReturnsNickNameOriginalRealNameAndClassName() {
        SchoolClass schoolClass = new SchoolClass();
        schoolClass.setId(2);
        schoolClass.setName("未分配");
        when(schoolClassService.selectById(2)).thenReturn(schoolClass);

        RestResponse<UserResponseVM> response = controller.current();

        assertEquals(1, response.getCode());
        assertEquals("old nick", response.getResponse().getNickName());
        assertEquals("Real Student", response.getResponse().getRealName());
        assertEquals(Integer.valueOf(2), response.getResponse().getClassId());
        assertEquals("未分配", response.getResponse().getClassName());
    }

    @Test
    public void currentDoesNotSetClassNameWhenUserHasNoClassId() {
        User user = user();
        user.setClassId(null);
        setCurrentUser(user);

        RestResponse<UserResponseVM> response = controller.current();

        assertEquals(1, response.getCode());
        assertNull(response.getResponse().getClassId());
        assertNull(response.getResponse().getClassName());
        verify(schoolClassService, never()).selectById(any());
    }

    @Test
    public void changePasswordRejectsWrongOldPassword() {
        User stored = user();
        when(userService.selectById(7)).thenReturn(stored);
        when(authenticationService.authUser(stored, "student", "old-pass")).thenReturn(false);

        RestResponse response = controller.changePassword(changePassword("old-pass", "new-pass", "new-pass"));

        assertEquals(2, response.getCode());
        verify(userService, never()).updateByIdFilter(any());
    }

    @Test
    public void changePasswordRejectsMismatchedConfirmation() {
        RestResponse response = controller.changePassword(changePassword("old-pass", "new-pass", "other-pass"));

        assertEquals(2, response.getCode());
        verify(userService, never()).selectById(any());
        verify(userService, never()).updateByIdFilter(any());
    }

    @Test
    public void changePasswordUpdatesEncodedPassword() {
        User stored = user();
        when(userService.selectById(7)).thenReturn(stored);
        when(authenticationService.authUser(stored, "student", "old-pass")).thenReturn(true);
        when(authenticationService.pwdEncode("new-pass")).thenReturn("encoded-new-pass");

        RestResponse response = controller.changePassword(changePassword("old-pass", "new-pass", "new-pass"));

        assertEquals(1, response.getCode());
        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userService).updateByIdFilter(captor.capture());
        assertEquals(Integer.valueOf(7), captor.getValue().getId());
        assertEquals("encoded-new-pass", captor.getValue().getPassword());
        assertNotNull(captor.getValue().getModifyTime());
    }

    private User user() {
        User user = new User();
        user.setId(7);
        user.setUserName("student");
        user.setRealName("Real Student");
        user.setNickName("old nick");
        user.setPhone("18800000000");
        user.setAge(16);
        user.setSex(2);
        user.setBirthDay(new Date(0));
        user.setUserLevel(3);
        user.setClassId(2);
        return user;
    }

    private void setCurrentUser(User user) {
        when(webContext.getCurrentUser()).thenReturn(user);
    }

    private StudentChangePasswordVM changePassword(String oldPassword, String newPassword, String confirmPassword) {
        StudentChangePasswordVM vm = new StudentChangePasswordVM();
        vm.setOldPassword(oldPassword);
        vm.setNewPassword(newPassword);
        vm.setConfirmPassword(confirmPassword);
        return vm;
    }
}
