package com.mindskip.xzs.configuration.spring;

import org.flywaydb.core.api.FlywayException;
import org.junit.Test;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.MapConfigurationPropertySource;

import java.sql.SQLException;
import java.sql.SQLTransientConnectionException;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class RetryingFlywayMigrationStrategyTest {

    @Test
    public void retryPropertiesUseFlyColdStartDefaults() {
        FlywayMigrationRetryProperties properties = new FlywayMigrationRetryProperties();

        assertEquals(Duration.ofSeconds(180), properties.getMaxWait());
        assertEquals(Duration.ofSeconds(5), properties.getInterval());
    }

    @Test
    public void retryPropertiesBindDurationValues() {
        Map<String, String> values = new HashMap<String, String>();
        values.put("xzs.flyway.retry.max-wait", "30s");
        values.put("xzs.flyway.retry.interval", "250ms");

        FlywayMigrationRetryProperties properties = new Binder(new MapConfigurationPropertySource(values))
                .bind("xzs.flyway.retry", Bindable.of(FlywayMigrationRetryProperties.class))
                .get();

        assertEquals(Duration.ofSeconds(30), properties.getMaxWait());
        assertEquals(Duration.ofMillis(250), properties.getInterval());
    }

    @Test
    public void sqlConnectionFailureIsRetryable() {
        FlywayException exception = new FlywayException(
                "Unable to obtain connection from database",
                new SQLException("connection refused", "08001"));

        assertTrue(RetryingFlywayMigrationStrategy.isRetryableConnectionFailure(exception));
    }

    @Test
    public void transientConnectionExceptionIsRetryableWithoutSqlState() {
        FlywayException exception = new FlywayException(
                "Unable to obtain connection from database",
                new SQLTransientConnectionException("timeout"));

        assertTrue(RetryingFlywayMigrationStrategy.isRetryableConnectionFailure(exception));
    }

    @Test
    public void migrationSyntaxFailureIsNotRetryable() {
        FlywayException exception = new FlywayException(
                "Migration failed",
                new SQLException("syntax error", "42601"));

        assertFalse(RetryingFlywayMigrationStrategy.isRetryableConnectionFailure(exception));
    }
}
