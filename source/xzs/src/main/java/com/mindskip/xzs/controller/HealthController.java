package com.mindskip.xzs.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.Statement;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/health")
public class HealthController {

    private final DataSource dataSource;

    public HealthController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @RequestMapping(method = {RequestMethod.GET, RequestMethod.HEAD})
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> database = checkDatabase();
        boolean up = "UP".equals(database.get("status"));

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", up ? "UP" : "DOWN");
        body.put("database", database);
        body.put("timestamp", Instant.now().toString());

        return new ResponseEntity<>(body, up ? HttpStatus.OK : HttpStatus.SERVICE_UNAVAILABLE);
    }

    private Map<String, Object> checkDatabase() {
        Map<String, Object> result = new LinkedHashMap<>();
        try (Connection connection = dataSource.getConnection();
             Statement statement = connection.createStatement()) {
            statement.execute("select 1");
            result.put("status", "UP");
        } catch (Exception e) {
            result.put("status", "DOWN");
            result.put("error", e.getClass().getSimpleName());
        }
        return result;
    }
}
