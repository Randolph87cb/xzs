package com.mindskip.xzs.configuration.spring;

import java.io.UnsupportedEncodingException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLDecoder;

/**
 * Adapts Postgres URL-style datasource values to Spring JDBC datasource properties.
 */
public final class FlyPostgresEnvironment {

    private FlyPostgresEnvironment() {
    }

    public static void apply() {
        String datasourceProperty = System.getProperty("spring.datasource.url");
        if (hasText(datasourceProperty)) {
            applyParsedUrl(datasourceProperty, false);
            return;
        }

        String springDatasourceUrl = System.getenv("SPRING_DATASOURCE_URL");
        if (hasText(springDatasourceUrl)) {
            applyParsedUrl(springDatasourceUrl, true);
            return;
        }

        String databaseUrl = System.getenv("DATABASE_URL");
        if (!hasText(databaseUrl)) {
            return;
        }

        applyParsedUrl(databaseUrl, true);
    }

    private static void applyParsedUrl(String url, boolean readCredentialsFromUrl) {
        if (url.startsWith("jdbc:postgresql://")) {
            return;
        }

        ParsedPostgresUrl parsed = parse(url);
        System.setProperty("spring.datasource.url", parsed.jdbcUrl);

        if (readCredentialsFromUrl && hasText(parsed.username) && !hasText(System.getenv("SPRING_DATASOURCE_USERNAME"))) {
            System.setProperty("spring.datasource.username", parsed.username);
        }

        if (readCredentialsFromUrl && hasText(parsed.password) && !hasText(System.getenv("SPRING_DATASOURCE_PASSWORD"))) {
            System.setProperty("spring.datasource.password", parsed.password);
        }
    }

    static ParsedPostgresUrl parse(String databaseUrl) {
        try {
            URI uri = new URI(databaseUrl);
            String scheme = uri.getScheme();
            if (!"postgres".equalsIgnoreCase(scheme) && !"postgresql".equalsIgnoreCase(scheme)) {
                throw new IllegalArgumentException("Postgres URL must use postgres:// or postgresql:// scheme.");
            }

            String host = uri.getHost();
            String path = uri.getPath();
            if (!hasText(host) || !hasText(path) || "/".equals(path)) {
                throw new IllegalArgumentException("Postgres URL must include host and database name.");
            }

            int port = uri.getPort() > 0 ? uri.getPort() : 5432;
            StringBuilder jdbcUrl = new StringBuilder("jdbc:postgresql://")
                    .append(host)
                    .append(':')
                    .append(port)
                    .append(path);
            String query = normalizeQuery(uri.getRawQuery());
            if (hasText(query)) {
                jdbcUrl.append('?').append(query);
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
            throw new IllegalArgumentException("Postgres URL is not a valid URI.", ex);
        }
    }

    private static String normalizeQuery(String rawQuery) {
        if (!hasText(rawQuery)) {
            return rawQuery;
        }

        StringBuilder normalized = new StringBuilder();
        String[] parts = rawQuery.split("&");
        for (String part : parts) {
            if (!hasText(part) || part.startsWith("channel_binding=")) {
                continue;
            }
            if (normalized.length() > 0) {
                normalized.append('&');
            }
            normalized.append(part);
        }
        return normalized.toString();
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

    static final class ParsedPostgresUrl {
        final String jdbcUrl;
        final String username;
        final String password;

        private ParsedPostgresUrl(String jdbcUrl, String username, String password) {
            this.jdbcUrl = jdbcUrl;
            this.username = username;
            this.password = password;
        }
    }
}
