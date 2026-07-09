package com.mindskip.xzs;

import org.junit.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;

public class ApplicationContextStartupTest {

    @Test
    public void applicationContextStartsWithoutCircularReferences() {
        ConfigurableApplicationContext context = new SpringApplicationBuilder(XzsApplication.class)
                .web(WebApplicationType.SERVLET)
                .run(
                        "--spring.profiles.active=test",
                        "--server.port=0",
                        "--spring.main.allow-circular-references=false",
                        "--spring.flyway.enabled=false",
                        "--spring.datasource.hikari.initialization-fail-timeout=-1",
                        "--spring.datasource.hikari.connection-timeout=1000",
                        "--spring.datasource.hikari.validation-timeout=1000"
                );

        context.close();
    }
}
