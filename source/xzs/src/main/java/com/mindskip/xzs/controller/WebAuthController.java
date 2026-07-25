package com.mindskip.xzs.controller;

import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.base.SystemCode;
import com.mindskip.xzs.configuration.spring.security.AuthenticationBean;
import com.mindskip.xzs.configuration.spring.security.WebAuthCookie;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.UserEventLog;
import com.mindskip.xzs.domain.UserToken;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.domain.enums.UserStatusEnum;
import com.mindskip.xzs.event.UserEvent;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.service.UserTokenService;
import com.mindskip.xzs.viewmodel.student.user.UserResponseVM;
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
import java.util.function.Function;

@RestController
@RequestMapping(value = "/api")
public class WebAuthController {

    private final AuthenticationService authenticationService;
    private final UserService userService;
    private final UserTokenService userTokenService;
    private final SchoolClassService schoolClassService;
    private final ApplicationEventPublisher eventPublisher;

    @Autowired
    public WebAuthController(AuthenticationService authenticationService, UserService userService, UserTokenService userTokenService, SchoolClassService schoolClassService, ApplicationEventPublisher eventPublisher) {
        this.authenticationService = authenticationService;
        this.userService = userService;
        this.userTokenService = userTokenService;
        this.schoolClassService = schoolClassService;
        this.eventPublisher = eventPublisher;
    }

    @RequestMapping(value = "/admin/auth/login", method = RequestMethod.POST)
    public RestResponse<User> adminLogin(@RequestBody AuthenticationBean model, HttpServletRequest request, HttpServletResponse response) {
        return login(model, WebAuthCookie.ADMIN_COOKIE_NAME, WebAuthCookie.ADMIN_COOKIE_PATH, request, response,
                this::toAdminLoginResponse, RoleEnum.ADMIN, RoleEnum.TEACHER);
    }

    @RequestMapping(value = "/student/auth/login", method = RequestMethod.POST)
    public RestResponse<UserResponseVM> studentLogin(@RequestBody AuthenticationBean model, HttpServletRequest request, HttpServletResponse response) {
        return login(model, WebAuthCookie.STUDENT_COOKIE_NAME, WebAuthCookie.STUDENT_COOKIE_PATH, request, response,
                this::toStudentLoginResponse, RoleEnum.STUDENT);
    }

    @RequestMapping(value = "/admin/auth/logout", method = RequestMethod.POST)
    public RestResponse adminLogout(HttpServletRequest request, HttpServletResponse response) {
        return logout(WebAuthCookie.ADMIN_COOKIE_NAME, WebAuthCookie.ADMIN_COOKIE_PATH, request, response);
    }

    @RequestMapping(value = "/student/auth/logout", method = RequestMethod.POST)
    public RestResponse studentLogout(HttpServletRequest request, HttpServletResponse response) {
        return logout(WebAuthCookie.STUDENT_COOKIE_NAME, WebAuthCookie.STUDENT_COOKIE_PATH, request, response);
    }

    private <T> RestResponse<T> login(AuthenticationBean model, String cookieName, String cookiePath,
                                      HttpServletRequest request, HttpServletResponse response,
                                      Function<User, T> responseMapper, RoleEnum... allowedRoles) {
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
        if (!isAllowedRole(RoleEnum.fromCode(user.getRole()), allowedRoles)) {
            return RestResponse.fail(SystemCode.AccessDenied.getCode(), "账号类型不匹配");
        }

        UserToken userToken = userTokenService.insertWebUserToken(user);
        WebAuthCookie.add(request, response, cookieName, userToken.getToken(), cookiePath, model.isRemember());
        publishEvent(user, " 登录了信息学客观题一本通");

        return RestResponse.ok(responseMapper.apply(user));
    }

    private User toAdminLoginResponse(User user) {
        User responseUser = new User();
        responseUser.setUserName(user.getUserName());
        responseUser.setImagePath(user.getImagePath());
        return responseUser;
    }

    private UserResponseVM toStudentLoginResponse(User user) {
        UserResponseVM vm = UserResponseVM.from(user);
        if (user.getClassId() != null) {
            SchoolClass schoolClass = schoolClassService.selectById(user.getClassId());
            if (schoolClass != null) {
                vm.setClassName(schoolClass.getName());
            }
        }
        return vm;
    }

    private boolean isAllowedRole(RoleEnum role, RoleEnum... allowedRoles) {
        if (null == role || null == allowedRoles) {
            return false;
        }
        for (RoleEnum allowedRole : allowedRoles) {
            if (role == allowedRole) {
                return true;
            }
        }
        return false;
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
