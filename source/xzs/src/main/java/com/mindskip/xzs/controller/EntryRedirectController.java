package com.mindskip.xzs.controller;

import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.ResponseBody;

import java.net.URI;

@Controller
public class EntryRedirectController {

    private static final String STUDENT_INDEX_RESOURCE = "classpath:/static/student/index.html";
    private static final MediaType HTML_UTF8 = MediaType.parseMediaType("text/html;charset=UTF-8");

    private final Resource studentIndex;

    public EntryRedirectController(ResourceLoader resourceLoader) {
        this.studentIndex = resourceLoader.getResource(STUDENT_INDEX_RESOURCE);
    }

    @RequestMapping(value = "/", method = {RequestMethod.GET, RequestMethod.HEAD})
    @ResponseBody
    public ResponseEntity<Resource> root() {
        return ResponseEntity.ok()
                .contentType(HTML_UTF8)
                .cacheControl(CacheControl.noStore())
                .body(studentIndex);
    }

    @RequestMapping(value = "/student", method = {RequestMethod.GET, RequestMethod.HEAD})
    public ResponseEntity<Void> student() {
        return relativeRedirect("student/index.html");
    }

    @RequestMapping(value = "/student/", method = {RequestMethod.GET, RequestMethod.HEAD})
    public ResponseEntity<Void> studentSlash() {
        return relativeRedirect("index.html");
    }

    @RequestMapping(value = "/admin", method = {RequestMethod.GET, RequestMethod.HEAD})
    public ResponseEntity<Void> admin() {
        return relativeRedirect("admin/index.html");
    }

    @RequestMapping(value = "/admin/", method = {RequestMethod.GET, RequestMethod.HEAD})
    public ResponseEntity<Void> adminSlash() {
        return relativeRedirect("index.html");
    }

    private ResponseEntity<Void> relativeRedirect(String location) {
        HttpHeaders headers = new HttpHeaders();
        headers.setLocation(URI.create(location));
        return new ResponseEntity<>(headers, HttpStatus.FOUND);
    }
}
