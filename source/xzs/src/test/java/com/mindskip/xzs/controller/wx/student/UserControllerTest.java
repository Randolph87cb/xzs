package com.mindskip.xzs.controller.wx.student;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WxContext;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.MessageService;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.service.UserEventLogService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.viewmodel.student.user.UserResponseVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

public class UserControllerTest {

    private SchoolClassService schoolClassService;
    private WxContext wxContext;
    private UserController controller;

    @Before
    public void setUp() {
        schoolClassService = mock(SchoolClassService.class);
        controller = new UserController(
                mock(UserService.class),
                mock(UserEventLogService.class),
                mock(MessageService.class),
                mock(AuthenticationService.class),
                schoolClassService,
                mock(ApplicationEventPublisher.class));

        wxContext = mock(WxContext.class);
        setCurrentUser(user());
        ReflectionTestUtils.setField(controller, "wxContext", wxContext);
    }

    @Test
    public void currentReturnsClassIdAndClassName() {
        SchoolClass schoolClass = new SchoolClass();
        schoolClass.setId(2);
        schoolClass.setName("未分配");
        when(schoolClassService.selectById(2)).thenReturn(schoolClass);

        RestResponse<UserResponseVM> response = controller.current();

        assertEquals(1, response.getCode());
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

    private User user() {
        User user = new User();
        user.setId(7);
        user.setUserName("student");
        user.setRealName("Real Student");
        user.setNickName("old nick");
        user.setClassId(2);
        return user;
    }

    private void setCurrentUser(User user) {
        when(wxContext.getCurrentUser()).thenReturn(user);
    }
}
