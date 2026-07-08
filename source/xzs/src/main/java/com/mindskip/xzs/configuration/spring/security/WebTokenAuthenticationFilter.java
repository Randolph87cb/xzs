package com.mindskip.xzs.configuration.spring.security;

import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.UserToken;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.domain.enums.UserStatusEnum;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.service.UserTokenService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Collections;
import java.util.Date;
import java.util.UUID;

@Component
public class WebTokenAuthenticationFilter extends OncePerRequestFilter {

    private final UserTokenService userTokenService;
    private final UserService userService;

    @Autowired
    public WebTokenAuthenticationFilter(UserTokenService userTokenService, UserService userService) {
        this.userTokenService = userTokenService;
        this.userService = userService;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        return !path.startsWith("/api/admin/") && !path.startsWith("/api/student/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        String path = request.getServletPath();
        RoleEnum role = path.startsWith("/api/admin/") ? RoleEnum.ADMIN : RoleEnum.STUDENT;
        String cookieName = RoleEnum.ADMIN == role ? WebAuthCookie.ADMIN_COOKIE_NAME : WebAuthCookie.STUDENT_COOKIE_NAME;
        String token = WebAuthCookie.read(request, cookieName);

        SecurityContextHolder.clearContext();
        if (isUuid(token)) {
            UserToken userToken = userTokenService.getToken(token);
            User user = resolveUser(userToken, role);
            if (null != user) {
                org.springframework.security.core.userdetails.User springUser =
                        new org.springframework.security.core.userdetails.User(
                                user.getUserName(),
                                user.getPassword(),
                                Collections.singletonList(new SimpleGrantedAuthority(role.getRoleName())));
                UsernamePasswordAuthenticationToken authentication =
                        new UsernamePasswordAuthenticationToken(springUser, springUser.getPassword(), springUser.getAuthorities());
                SecurityContextHolder.getContext().setAuthentication(authentication);
            }
        }

        filterChain.doFilter(request, response);
    }

    private User resolveUser(UserToken userToken, RoleEnum role) {
        if (null == userToken || null == userToken.getEndTime() || !new Date().before(userToken.getEndTime())) {
            return null;
        }
        User user = userService.getUserByUserName(userToken.getUserName());
        if (null == user || Boolean.TRUE.equals(user.getDeleted())) {
            return null;
        }
        if (UserStatusEnum.Enable != UserStatusEnum.fromCode(user.getStatus())) {
            return null;
        }
        if (RoleEnum.fromCode(user.getRole()) != role) {
            return null;
        }
        return user;
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
