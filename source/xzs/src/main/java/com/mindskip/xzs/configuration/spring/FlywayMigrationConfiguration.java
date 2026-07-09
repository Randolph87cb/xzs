package com.mindskip.xzs.configuration.spring;

import org.springframework.boot.autoconfigure.flyway.FlywayMigrationStrategy;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties(FlywayMigrationRetryProperties.class)
public class FlywayMigrationConfiguration {

    @Bean
    public FlywayMigrationStrategy flywayMigrationStrategy(FlywayMigrationRetryProperties properties) {
        return new RetryingFlywayMigrationStrategy(properties);
    }
}
