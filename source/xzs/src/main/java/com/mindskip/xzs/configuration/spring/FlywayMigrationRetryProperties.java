package com.mindskip.xzs.configuration.spring;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;

@ConfigurationProperties(prefix = "xzs.flyway.retry")
public class FlywayMigrationRetryProperties {

    private Duration maxWait = Duration.ofSeconds(180);
    private Duration interval = Duration.ofSeconds(5);

    public Duration getMaxWait() {
        return maxWait;
    }

    public void setMaxWait(Duration maxWait) {
        this.maxWait = maxWait;
    }

    public Duration getInterval() {
        return interval;
    }

    public void setInterval(Duration interval) {
        this.interval = interval;
    }
}
