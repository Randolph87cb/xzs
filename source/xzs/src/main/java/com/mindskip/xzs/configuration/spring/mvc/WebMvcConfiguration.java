package com.mindskip.xzs.configuration.spring.mvc;

import com.mindskip.xzs.configuration.property.SystemConfig;
import com.mindskip.xzs.configuration.spring.wx.TokenHandlerInterceptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.http.CacheControl;
import org.springframework.web.servlet.config.annotation.*;

import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;


/**
 * @version 3.5.0
 * @description: The type Web mvc configuration.
 * Copyright (C), 2020-2026, 武汉思维跳跃科技有限公司
 * @date 2021/12/25 9:45
 */
@Configuration
public class WebMvcConfiguration extends WebMvcConfigurationSupport {

    private static final int NO_CACHE_SECONDS = 0;
    private static final String DEV_PROFILE = "dev";
    private static final String CLASSPATH_STATIC = "classpath:/static/";
    private static final String CLASSPATH_ADMIN_STATIC = "classpath:/static/admin/static/";
    private static final String CLASSPATH_STUDENT_STATIC = "classpath:/static/student/static/";
    private static final String ADMIN_ROOT_PROPERTY = "xzs.web.static.admin-root";
    private static final String STUDENT_ROOT_PROPERTY = "xzs.web.static.student-root";
    private static final String DEFAULT_ADMIN_ROOT = "../../frontend/apps/admin/";
    private static final String DEFAULT_STUDENT_ROOT = "../../frontend/apps/student/";

    private final TokenHandlerInterceptor tokenHandlerInterceptor;
    private final SystemConfig systemConfig;
    private final Environment environment;

    /**
     * Instantiates a new Web mvc configuration.
     *
     * @param tokenHandlerInterceptor the token handler interceptor
     * @param systemConfig            the system config
     */
    @Autowired
    public WebMvcConfiguration(TokenHandlerInterceptor tokenHandlerInterceptor, SystemConfig systemConfig, Environment environment) {
        this.tokenHandlerInterceptor = tokenHandlerInterceptor;
        this.systemConfig = systemConfig;
        this.environment = environment;
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        if (isDevProfile()) {
            addDevResourceHandlers(registry);
            return;
        }

        registry.addResourceHandler("/admin/static/**")
                .addResourceLocations(CLASSPATH_ADMIN_STATIC)
                .setCacheControl(CacheControl.maxAge(365, TimeUnit.DAYS).cachePublic());

        registry.addResourceHandler("/student/static/**")
                .addResourceLocations(CLASSPATH_STUDENT_STATIC)
                .setCacheControl(CacheControl.maxAge(365, TimeUnit.DAYS).cachePublic());

        registry.addResourceHandler("/admin/index.html", "/student/index.html")
                .addResourceLocations(CLASSPATH_STATIC)
                .setCachePeriod(NO_CACHE_SECONDS);

        registry.addResourceHandler("/**")
                .addResourceLocations(CLASSPATH_STATIC)
                .setCachePeriod(NO_CACHE_SECONDS);
    }

    private void addDevResourceHandlers(ResourceHandlerRegistry registry) {
        String adminRoot = normalizeRootLocation(environment.getProperty(ADMIN_ROOT_PROPERTY, DEFAULT_ADMIN_ROOT));
        String studentRoot = normalizeRootLocation(environment.getProperty(STUDENT_ROOT_PROPERTY, DEFAULT_STUDENT_ROOT));

        registry.addResourceHandler("/admin/static/**")
                .addResourceLocations(fileLocation(adminRoot, "admin/static/"), CLASSPATH_ADMIN_STATIC)
                .setCacheControl(CacheControl.noStore());

        registry.addResourceHandler("/student/static/**")
                .addResourceLocations(fileLocation(studentRoot, "student/static/"), CLASSPATH_STUDENT_STATIC)
                .setCacheControl(CacheControl.noStore());

        registry.addResourceHandler("/admin/index.html", "/student/index.html")
                .addResourceLocations(fileLocation(adminRoot), fileLocation(studentRoot), CLASSPATH_STATIC)
                .setCacheControl(CacheControl.noStore());

        registry.addResourceHandler("/**")
                .addResourceLocations(fileLocation(adminRoot), fileLocation(studentRoot), CLASSPATH_STATIC)
                .setCacheControl(CacheControl.noStore());
    }

    private boolean isDevProfile() {
        return Arrays.asList(environment.getActiveProfiles()).contains(DEV_PROFILE);
    }

    private String normalizeRootLocation(String root) {
        String trimmedRoot = root.trim();
        if (trimmedRoot.endsWith("/") || trimmedRoot.endsWith("\\")) {
            return trimmedRoot;
        }
        return trimmedRoot + "/";
    }

    private String fileLocation(String root) {
        return "file:" + root;
    }

    private String fileLocation(String root, String path) {
        return fileLocation(root) + path;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        List<String> securityIgnoreUrls = systemConfig.getWx().getSecurityIgnoreUrls();
        String[] ignores = new String[securityIgnoreUrls.size()];
        registry.addInterceptor(tokenHandlerInterceptor)
                .addPathPatterns("/api/wx/**")
                .excludePathPatterns(securityIgnoreUrls.toArray(ignores));
        super.addInterceptors(registry);
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                .allowCredentials(true)
                .allowedMethods("*")
                .allowedOriginPatterns("*")
                .allowedHeaders("*");
        super.addCorsMappings(registry);
    }

}
