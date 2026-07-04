package com.mindskip.xzs.configuration.spring;

import java.io.UnsupportedEncodingException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLDecoder;

/**
 * Adapts Fly Managed Postgres DATABASE_URL to Spring JDBC datasource properties.
 */
public final class FlyPostgresEnvironment {

    private FlyPostgresEnvironment() {
    }

    public static void apply() {
        if (hasText(System.getenv("SPRING_DATASOURCE_URL")) || hasText(System.getProperty("spring.datasource.url"))) {
            return;
        }

        String databaseUrl = System.getenv("DATABASE_URL");
        if (!hasText(databaseUrl)) {
            return;
        }

        ParsedPostgresUrl parsed = parse(databaseUrl);
        System.setProperty("spring.datasource.url", parsed.jdbcUrl);

        if (hasText(parsed.username) && !hasText(System.getenv("SPRING_DATASOURCE_USERNAME"))) {
            System.setProperty("spring.datasource.username", parsed.username);
        }

        if (hasText(parsed.password) && !hasText(System.getenv("SPRING_DATASOURCE_PASSWORD"))) {
            System.setProperty("spring.datasource.password", parsed.password);
        }
    }

    private static ParsedPostgresUrl parse(String databaseUrl) {
        try {
            URI uri = new URI(databaseUrl);
            String scheme = uri.getScheme();
            if (!"postgres".equalsIgnoreCase(scheme) && !"postgresql".equalsIgnoreCase(scheme)) {
                throw new IllegalArgumentException("DATABASE_URL must use postgres:// or postgresql:// scheme.");
            }

            String host = uri.getHost();
            String path = uri.getPath();
            if (!hasText(host) || !hasText(path) || "/".equals(path)) {
                throw new IllegalArgumentException("DATABASE_URL must include host and database name.");
            }

            int port = uri.getPort() > 0 ? uri.getPort() : 5432;
            StringBuilder jdbcUrl = new StringBuilder("jdbc:postgresql://")
                    .append(host)
                    .append(':')
                    .append(port)
                    .append(path);
            if (hasText(uri.getQuery())) {
                jdbcUrl.append('?').append(uri.getQuery());
            }

            String username = null;
            String password = null;
            String userInfo = uri.getRawUserInfo();
            if (hasText(userInfo)) {
                int separator = userInfo.indexOf(':');
                if (separator >= 0) {
                    username = decode(userInfo.substring(0, separator));
                    password = decode(userInfo.substring(separator + 1));
                } else {
                    username = decode(userInfo);
                }
            }

            return new ParsedPostgresUrl(jdbcUrl.toString(), username, password);
        } catch (URISyntaxException ex) {
            throw new IllegalArgumentException("DATABASE_URL is not a valid URI.", ex);
        }
    }

    private static String decode(String value) {
        try {
            return URLDecoder.decode(value, "UTF-8");
        } catch (UnsupportedEncodingException ex) {
            throw new IllegalStateException("UTF-8 is not available.", ex);
        }
    }

    private static boolean hasText(String value) {
        return value != null && value.trim().length() > 0;
    }

    private static final class ParsedPostgresUrl {
        private final String jdbcUrl;
        private final String username;
        private final String password;

        private ParsedPostgresUrl(String jdbcUrl, String username, String password) {
            this.jdbcUrl = jdbcUrl;
            this.username = username;
            this.password = password;
        }
    }
}
