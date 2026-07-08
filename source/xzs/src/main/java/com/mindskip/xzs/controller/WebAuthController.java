package com.mindskip.xzs.controller;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.base.SystemCode;
import com.mindskip.xzs.configuration.spring.security.AuthenticationBean;
import com.mindskip.xzs.configuration.spring.security.WebAuthCookie;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.UserEventLog;
import com.mindskip.xzs.domain.UserToken;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.domain.enums.UserStatusEnum;
import com.mindskip.xzs.event.UserEvent;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.service.UserTokenService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.Date;
import java.util.UUID;

@RestController
@RequestMapping(value = "/api")
public class WebAuthController {

    private final AuthenticationService authenticationService;
    private final UserService userService;
    private final UserTokenService userTokenService;
    private final ApplicationEventPublisher eventPublisher;

    @Autowired
    public WebAuthController(AuthenticationService authenticationService, UserService userService, UserTokenService userTokenService, ApplicationEventPublisher eventPublisher) {
        this.authenticationService = authenticationService;
        this.userService = userService;
        this.userTokenService = userTokenService;
        this.eventPublisher = eventPublisher;
    }

    @RequestMapping(value = "/admin/auth/login", method = RequestMethod.POST)
    public RestResponse<User> adminLogin(@RequestBody AuthenticationBean model, HttpServletRequest request, HttpServletResponse response) {
        return login(model, RoleEnum.ADMIN, WebAuthCookie.ADMIN_COOKIE_NAME, WebAuthCookie.ADMIN_COOKIE_PATH, request, response);
    }

    @RequestMapping(value = "/student/auth/login", method = RequestMethod.POST)
    public RestResponse<User> studentLogin(@RequestBody AuthenticationBean model, HttpServletRequest request, HttpServletResponse response) {
        return login(model, RoleEnum.STUDENT, WebAuthCookie.STUDENT_COOKIE_NAME, WebAuthCookie.STUDENT_COOKIE_PATH, request, response);
    }

    @RequestMapping(value = "/admin/auth/logout", method = RequestMethod.POST)
    public RestResponse adminLogout(HttpServletRequest request, HttpServletResponse response) {
        return logout(WebAuthCookie.ADMIN_COOKIE_NAME, WebAuthCookie.ADMIN_COOKIE_PATH, request, response);
    }

    @RequestMapping(value = "/student/auth/logout", method = RequestMethod.POST)
    public RestResponse studentLogout(HttpServletRequest request, HttpServletResponse response) {
        return logout(WebAuthCookie.STUDENT_COOKIE_NAME, WebAuthCookie.STUDENT_COOKIE_PATH, request, response);
    }

    private RestResponse<User> login(AuthenticationBean model, RoleEnum role, String cookieName, String cookiePath, HttpServletRequest request, HttpServletResponse response) {
        if (null == model) {
            return RestResponse.fail(SystemCode.AuthError.getCode(), SystemCode.AuthError.getMessage());
        }
        User user = userService.getUserByUserName(model.getUserName());
        if (null == user || !authenticationService.authUser(user, model.getUserName(), model.getPassword())) {
            return RestResponse.fail(SystemCode.AuthError.getCode(), SystemCode.AuthError.getMessage());
        }
        if (Boolean.TRUE.equals(user.getDeleted()) || UserStatusEnum.Enable != UserStatusEnum.fromCode(user.getStatus())) {
            return RestResponse.fail(SystemCode.AccessDenied.getCode(), "用户被禁用");
        }
        if (RoleEnum.fromCode(user.getRole()) != role) {
            return RestResponse.fail(SystemCode.AccessDenied.getCode(), "账号类型不匹配");
        }

        UserToken userToken = userTokenService.insertWebUserToken(user);
        WebAuthCookie.add(request, response, cookieName, userToken.getToken(), cookiePath, model.isRemember());
        publishEvent(user, " 登录了学之思开源考试系统");

        User responseUser = new User();
        responseUser.setUserName(user.getUserName());
        responseUser.setImagePath(user.getImagePath());
        return RestResponse.ok(responseUser);
    }

    private RestResponse logout(String cookieName, String cookiePath, HttpServletRequest request, HttpServletResponse response) {
        String token = WebAuthCookie.read(request, cookieName);
        if (isUuid(token)) {
            userTokenService.deleteByToken(token);
        }
        WebAuthCookie.remove(request, response, cookieName, cookiePath);
        return RestResponse.ok();
    }

    private void publishEvent(User user, String content) {
        UserEventLog userEventLog = new UserEventLog(user.getId(), user.getUserName(), user.getRealName(), new Date());
        userEventLog.setContent(user.getUserName() + content);
        eventPublisher.publishEvent(new UserEvent(userEventLog));
    }

    private boolean isUuid(String value) {
        if (null == value) {
            return false;
        }
        try {
            UUID.fromString(value);
            return true;
        } catch (IllegalArgumentException e) {
            return false;
        }
    }
}
