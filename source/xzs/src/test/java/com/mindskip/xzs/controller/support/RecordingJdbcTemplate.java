package com.mindskip.xzs.controller.support;

import org.springframework.jdbc.core.JdbcTemplate;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Queue;

public class RecordingJdbcTemplate extends JdbcTemplate {

    public static class Call {
        private final String method;
        private final String sql;
        private final Object[] args;

        private Call(String method, String sql, Object[] args) {
            this.method = method;
            this.sql = sql;
            this.args = args == null ? new Object[0] : args.clone();
        }

        public String getMethod() {
            return method;
        }

        public String getSql() {
            return sql;
        }

        public Object[] getArgs() {
            return args.clone();
        }
    }

    private final List<Call> calls = new ArrayList<>();
    private final Queue<Object> queryForObjectResults = new ArrayDeque<>();
    private final Queue<List<Map<String, Object>>> queryForListResults = new ArrayDeque<>();

    public void addQueryForObjectResult(Object result) {
        queryForObjectResults.add(result);
    }

    public void addQueryForListResult(List<Map<String, Object>> result) {
        queryForListResults.add(result);
    }

    public List<Call> getCalls(String method) {
        List<Call> result = new ArrayList<>();
        for (Call call : calls) {
            if (method.equals(call.getMethod())) {
                result.add(call);
            }
        }
        return result;
    }

    @Override
    public <T> T queryForObject(String sql, Class<T> requiredType, Object... args) {
        calls.add(new Call("queryForObject", sql, args));
        Object result = queryForObjectResults.remove();
        return requiredType.cast(result);
    }

    @Override
    public List<Map<String, Object>> queryForList(String sql, Object... args) {
        calls.add(new Call("queryForList", sql, args));
        if (queryForListResults.isEmpty()) {
            return Collections.emptyList();
        }
        return queryForListResults.remove();
    }

    @Override
    public int update(String sql, Object... args) {
        calls.add(new Call("update", sql, args));
        return 1;
    }
}
