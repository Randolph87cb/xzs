package com.mindskip.xzs.configuration.spring.security;

import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.UserToken;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.domain.enums.UserStatusEnum;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.service.UserTokenService;
import org.junit.After;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import javax.servlet.FilterChain;
import javax.servlet.http.Cookie;
import java.util.Date;
import java.util.UUID;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

public class WebTokenAuthenticationFilterTest {

    @After
    public void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    public void adminPathAcceptsTeacherToken() throws Exception {
        String token = UUID.randomUUID().toString();
        UserToken userToken = token("teacher", token);
        User teacher = user("teacher", RoleEnum.TEACHER);

        UserTokenService userTokenService = mock(UserTokenService.class);
        UserService userService = mock(UserService.class);
        when(userTokenService.getToken(token)).thenReturn(userToken);
        when(userService.getUserByUserName("teacher")).thenReturn(teacher);

        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/admin/user/current");
        request.setServletPath("/api/admin/user/current");
        request.setCookies(new Cookie(WebAuthCookie.ADMIN_COOKIE_NAME, token));

        WebTokenAuthenticationFilter filter = new WebTokenAuthenticationFilter(userTokenService, userService);
        filter.doFilter(request, new MockHttpServletResponse(), mock(FilterChain.class));

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        assertNotNull(authentication);
        assertEquals("teacher", authentication.getName());
        assertEquals(RoleEnum.TEACHER.getRoleName(), authentication.getAuthorities().iterator().next().getAuthority());
    }

    @Test
    public void studentPathRejectsTeacherToken() throws Exception {
        String token = UUID.randomUUID().toString();
        UserToken userToken = token("teacher", token);
        User teacher = user("teacher", RoleEnum.TEACHER);

        UserTokenService userTokenService = mock(UserTokenService.class);
        UserService userService = mock(UserService.class);
        when(userTokenService.getToken(token)).thenReturn(userToken);
        when(userService.getUserByUserName("teacher")).thenReturn(teacher);

        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/student/user/current");
        request.setServletPath("/api/student/user/current");
        request.setCookies(new Cookie(WebAuthCookie.STUDENT_COOKIE_NAME, token));

        WebTokenAuthenticationFilter filter = new WebTokenAuthenticationFilter(userTokenService, userService);
        filter.doFilter(request, new MockHttpServletResponse(), mock(FilterChain.class));

        assertEquals(null, SecurityContextHolder.getContext().getAuthentication());
    }

    private UserToken token(String userName, String token) {
        UserToken userToken = new UserToken();
        userToken.setUserName(userName);
        userToken.setToken(token);
        userToken.setEndTime(new Date(System.currentTimeMillis() + 60000));
        return userToken;
    }

    private User user(String userName, RoleEnum role) {
        User user = new User();
        user.setUserName(userName);
        user.setPassword("pwd");
        user.setRole(role.getCode());
        user.setStatus(UserStatusEnum.Enable.getCode());
        user.setDeleted(false);
        return user;
    }
}
