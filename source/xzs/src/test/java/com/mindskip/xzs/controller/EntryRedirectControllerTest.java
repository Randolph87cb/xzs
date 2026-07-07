package com.mindskip.xzs.controller;

import org.junit.Before;
import org.junit.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.head;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class EntryRedirectControllerTest {

    private MockMvc mockMvc;

    @Before
    public void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(new EntryRedirectController()).build();
    }

    @Test
    public void rootRedirectsToStudentIndexWithRelativeLocation() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isFound())
                .andExpect(header().string("Location", "student/index.html"));
    }

    @Test
    public void headRootRedirectsToStudentIndexWithRelativeLocation() throws Exception {
        mockMvc.perform(head("/"))
                .andExpect(status().isFound())
                .andExpect(header().string("Location", "student/index.html"));
    }

    @Test
    public void studentRedirectsToStudentIndexWithRelativeLocation() throws Exception {
        mockMvc.perform(get("/student"))
                .andExpect(status().isFound())
                .andExpect(header().string("Location", "student/index.html"));
    }

    @Test
    public void adminRedirectsToAdminIndexWithRelativeLocation() throws Exception {
        mockMvc.perform(get("/admin"))
                .andExpect(status().isFound())
                .andExpect(header().string("Location", "admin/index.html"));
    }
}
