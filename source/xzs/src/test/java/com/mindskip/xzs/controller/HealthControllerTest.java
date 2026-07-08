package com.mindskip.xzs.controller;

import org.junit.Before;
import org.junit.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.head;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class HealthControllerTest {

    private DataSource dataSource;
    private Connection connection;
    private Statement statement;
    private MockMvc mockMvc;

    @Before
    public void setUp() throws Exception {
        dataSource = mock(DataSource.class);
        connection = mock(Connection.class);
        statement = mock(Statement.class);

        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.createStatement()).thenReturn(statement);
        when(statement.execute("select 1")).thenReturn(true);

        mockMvc = MockMvcBuilders.standaloneSetup(new HealthController(dataSource)).build();
    }

    @Test
    public void healthReturnsUpWhenDatabaseQuerySucceeds() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.database.status").value("UP"));
    }

    @Test
    public void headHealthReturnsOkWhenDatabaseQuerySucceeds() throws Exception {
        mockMvc.perform(head("/api/health"))
                .andExpect(status().isOk());
    }

    @Test
    public void healthReturnsServiceUnavailableWhenDatabaseQueryFails() throws Exception {
        when(dataSource.getConnection()).thenThrow(new SQLException("database unavailable"));

        mockMvc.perform(get("/api/health"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.status").value("DOWN"))
                .andExpect(jsonPath("$.database.status").value("DOWN"))
                .andExpect(jsonPath("$.database.error").value("SQLException"));
    }
}
