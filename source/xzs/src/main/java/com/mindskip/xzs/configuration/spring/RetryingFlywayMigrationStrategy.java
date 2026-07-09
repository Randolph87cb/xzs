package com.mindskip.xzs.configuration.spring;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.FlywayException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.flyway.FlywayMigrationStrategy;

import java.net.ConnectException;
import java.net.NoRouteToHostException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.sql.SQLException;
import java.sql.SQLNonTransientConnectionException;
import java.sql.SQLTransientConnectionException;
import java.time.Duration;

class RetryingFlywayMigrationStrategy implements FlywayMigrationStrategy {

    private static final Logger logger = LoggerFactory.getLogger(RetryingFlywayMigrationStrategy.class);
    private static final Duration DEFAULT_MAX_WAIT = Duration.ofSeconds(180);
    private static final Duration DEFAULT_INTERVAL = Duration.ofSeconds(5);

    private final FlywayMigrationRetryProperties properties;

    RetryingFlywayMigrationStrategy(FlywayMigrationRetryProperties properties) {
        this.properties = properties;
    }

    @Override
    public void migrate(Flyway flyway) {
        Duration maxWait = normalizedMaxWait();
        Duration interval = normalizedInterval();
        long startedAt = System.nanoTime();
        int attempt = 1;

        while (true) {
            try {
                flyway.migrate();
                if (attempt > 1) {
                    logger.info("Flyway migration completed after {} attempts.", attempt);
                }
                return;
            } catch (RuntimeException ex) {
                if (!isRetryableConnectionFailure(ex)) {
                    throw ex;
                }

                long elapsedMillis = elapsedMillis(startedAt);
                if (maxWait.isZero() || elapsedMillis >= maxWait.toMillis()) {
                    logger.error("Flyway migration still cannot connect to the database after {} and {} attempts. Startup will fail.",
                            format(maxWait), attempt, ex);
                    throw ex;
                }

                long sleepMillis = Math.min(interval.toMillis(), maxWait.toMillis() - elapsedMillis);
                if (sleepMillis <= 0) {
                    sleepMillis = 1;
                }

                logger.warn("Flyway migration cannot connect to the database yet (attempt {}, elapsed {}, retrying in {}). Cause: {}",
                        attempt, format(Duration.ofMillis(elapsedMillis)), format(Duration.ofMillis(sleepMillis)),
                        rootMessage(ex));
                sleep(sleepMillis);
                attempt++;
            }
        }
    }

    static boolean isRetryableConnectionFailure(Throwable throwable) {
        Throwable current = throwable;
        while (current != null) {
            if (current instanceof SQLTransientConnectionException || current instanceof SQLNonTransientConnectionException) {
                return true;
            }
            if (current instanceof SQLException && isRetryableSqlException((SQLException) current)) {
                return true;
            }
            if (current instanceof ConnectException
                    || current instanceof SocketTimeoutException
                    || current instanceof UnknownHostException
                    || current instanceof NoRouteToHostException) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }

    private static boolean isRetryableSqlException(SQLException exception) {
        SQLException current = exception;
        while (current != null) {
            String sqlState = current.getSQLState();
            if (sqlState != null) {
                if (sqlState.startsWith("08")) {
                    return true;
                }
                if ("57P03".equals(sqlState) || "53300".equals(sqlState) || "53400".equals(sqlState)) {
                    return true;
                }
            }
            current = current.getNextException();
        }
        return false;
    }

    private Duration normalizedMaxWait() {
        Duration maxWait = properties == null ? null : properties.getMaxWait();
        if (maxWait == null) {
            return DEFAULT_MAX_WAIT;
        }
        if (maxWait.isNegative()) {
            return Duration.ZERO;
        }
        return maxWait;
    }

    private Duration normalizedInterval() {
        Duration interval = properties == null ? null : properties.getInterval();
        if (interval == null || interval.isZero() || interval.isNegative()) {
            return DEFAULT_INTERVAL;
        }
        return interval;
    }

    private static long elapsedMillis(long startedAt) {
        return Duration.ofNanos(System.nanoTime() - startedAt).toMillis();
    }

    private static void sleep(long sleepMillis) {
        try {
            Thread.sleep(sleepMillis);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new FlywayException("Interrupted while waiting to retry Flyway migration.", ex);
        }
    }

    private static String rootMessage(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null) {
            current = current.getCause();
        }
        String message = current.getMessage();
        if (message == null || message.trim().length() == 0) {
            return current.getClass().getSimpleName();
        }
        return current.getClass().getSimpleName() + ": " + message;
    }

    private static String format(Duration duration) {
        long millis = duration.toMillis();
        if (millis < 1000) {
            return millis + "ms";
        }
        return (millis / 1000) + "s";
    }
}
