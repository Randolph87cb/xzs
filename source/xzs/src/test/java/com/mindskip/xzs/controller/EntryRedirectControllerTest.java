package com.mindskip.xzs.controller;

import org.junit.Before;
import org.junit.Test;
import org.springframework.core.io.DefaultResourceLoader;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.head;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class EntryRedirectControllerTest {

    private MockMvc mockMvc;

    @Before
    public void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(new EntryRedirectController(new DefaultResourceLoader())).build();
    }

    @Test
    public void rootReturnsStudentHtmlWithoutRedirect() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(containsString("<base href=\"/student/\" />")))
                .andExpect(content().string(containsString("<div id=\"app\"></div>")))
                .andExpect(header().doesNotExist("Location"));
    }

    @Test
    public void headRootReturnsHtmlHeadersWithoutRedirectBody() throws Exception {
        mockMvc.perform(head("/"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(""))
                .andExpect(header().doesNotExist("Location"));
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
