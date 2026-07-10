package com.mindskip.xzs.controller.wx.student;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.context.WxContext;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.MessageService;
import com.mindskip.xzs.service.UserEventLogService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.viewmodel.student.user.UserResponseVM;
import org.junit.Before;
import org.junit.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class UserControllerTest {

    private UserController controller;

    @Before
    public void setUp() {
        controller = new UserController(
                mock(UserService.class),
                mock(UserEventLogService.class),
                mock(MessageService.class),
                mock(AuthenticationService.class),
                mock(ApplicationEventPublisher.class));

        WxContext wxContext = mock(WxContext.class);
        when(wxContext.getCurrentUser()).thenReturn(user());
        ReflectionTestUtils.setField(controller, "wxContext", wxContext);
    }

    @Test
    public void currentReturnsClassId() {
        RestResponse<UserResponseVM> response = controller.current();

        assertEquals(1, response.getCode());
        assertEquals(Integer.valueOf(5), response.getResponse().getClassId());
    }

    private User user() {
        User user = new User();
        user.setId(7);
        user.setUserName("student");
        user.setRealName("Real Student");
        user.setNickName("old nick");
        user.setClassId(5);
        return user;
    }
}
