package com.mindskip.xzs.configuration.spring;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class FlyPostgresEnvironmentTest {

    @Test
    public void parseConvertsPostgresUrlToJdbcUrl() {
        FlyPostgresEnvironment.ParsedPostgresUrl parsed = FlyPostgresEnvironment.parse(
                "postgresql://neondb_owner:secret@example.neon.tech/neondb?sslmode=require&channel_binding=require");

        assertEquals("jdbc:postgresql://example.neon.tech:5432/neondb?sslmode=require", parsed.jdbcUrl);
        assertEquals("neondb_owner", parsed.username);
        assertEquals("secret", parsed.password);
    }
}
