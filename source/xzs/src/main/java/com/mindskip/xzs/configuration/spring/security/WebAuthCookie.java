package com.mindskip.xzs.configuration.spring.security;

import com.mindskip.xzs.configuration.property.CookieConfig;

import javax.servlet.http.Cookie;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public final class WebAuthCookie {

    public static final String ADMIN_COOKIE_NAME = "XZS_ADMIN_TOKEN";
    public static final String STUDENT_COOKIE_NAME = "XZS_STUDENT_TOKEN";
    public static final String ADMIN_COOKIE_PATH = "/api/admin";
    public static final String STUDENT_COOKIE_PATH = "/api/student";

    private WebAuthCookie() {
    }

    public static String read(HttpServletRequest request, String name) {
        Cookie[] cookies = request.getCookies();
        if (null == cookies) {
            return null;
        }
        for (Cookie cookie : cookies) {
            if (name.equals(cookie.getName())) {
                return cookie.getValue();
            }
        }
        return null;
    }

    public static void add(HttpServletRequest request, HttpServletResponse response, String name, String value, String path, boolean persistent) {
        response.addHeader("Set-Cookie", buildCookie(request, name, value, path, persistent ? CookieConfig.getInterval() : null));
    }

    public static void remove(HttpServletRequest request, HttpServletResponse response, String name, String path) {
        response.addHeader("Set-Cookie", buildCookie(request, name, "", path, 0));
    }

    private static String buildCookie(HttpServletRequest request, String name, String value, String path, Integer maxAge) {
        StringBuilder builder = new StringBuilder();
        builder.append(name).append('=').append(value)
                .append("; Path=").append(path)
                .append("; HttpOnly")
                .append("; SameSite=Lax");
        if (null != maxAge) {
            builder.append("; Max-Age=").append(maxAge);
        }
        if (isSecureRequest(request)) {
            builder.append("; Secure");
        }
        return builder.toString();
    }

    private static boolean isSecureRequest(HttpServletRequest request) {
        return request.isSecure() || "https".equalsIgnoreCase(request.getHeader("X-Forwarded-Proto"));
    }
}
