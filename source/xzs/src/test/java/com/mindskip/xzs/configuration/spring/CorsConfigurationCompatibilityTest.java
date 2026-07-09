package com.mindskip.xzs.configuration.spring;

import com.mindskip.xzs.configuration.property.SystemConfig;
import com.mindskip.xzs.configuration.spring.mvc.WebMvcConfiguration;
import com.mindskip.xzs.configuration.spring.security.SecurityConfigurer;
import com.mindskip.xzs.configuration.spring.wx.TokenHandlerInterceptor;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.servlet.config.annotation.CorsRegistry;

import java.util.Collections;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.mockito.Mockito.mock;

public class CorsConfigurationCompatibilityTest {

    @Test
    public void webMvcCorsUsesOriginPatternsWhenCredentialsAreAllowed() {
        CorsRegistry registry = new CorsRegistry();
        WebMvcConfiguration configuration = new WebMvcConfiguration(
                mock(TokenHandlerInterceptor.class),
                mock(SystemConfig.class));

        configuration.addCorsMappings(registry);

        Map<String, CorsConfiguration> corsConfigurations = ReflectionTestUtils.invokeMethod(registry, "getCorsConfigurations");
        CorsConfiguration corsConfiguration = corsConfigurations.get("/**");

        assertCredentialedWildcardPattern(corsConfiguration, "https://admin.example.com");
    }

    @Test
    public void securityCorsUsesOriginPatternsWhenCredentialsAreAllowed() {
        SecurityConfigurer.FormLoginWebSecurityConfigurerAdapter adapter =
                new SecurityConfigurer.FormLoginWebSecurityConfigurerAdapter(
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null);

        CorsConfigurationSource source = adapter.corsConfigurationSource();
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/health");
        request.addHeader("Origin", "https://student.example.com");

        CorsConfiguration corsConfiguration = source.getCorsConfiguration(request);

        assertCredentialedWildcardPattern(corsConfiguration, "https://student.example.com");
    }

    private void assertCredentialedWildcardPattern(CorsConfiguration corsConfiguration, String origin) {
        assertNotNull(corsConfiguration);
        assertEquals(Boolean.TRUE, corsConfiguration.getAllowCredentials());
        assertEquals(Collections.singletonList("*"), corsConfiguration.getAllowedOriginPatterns());
        corsConfiguration.validateAllowCredentials();
        assertEquals(origin, corsConfiguration.checkOrigin(origin));
    }
}
