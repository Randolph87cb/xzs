package com.mindskip.xzs.controller;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;

import java.net.URI;

@Controller
public class EntryRedirectController {

    @RequestMapping(value = "/", method = {RequestMethod.GET, RequestMethod.HEAD})
    public ResponseEntity<Void> root() {
        return relativeRedirect("student/index.html");
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
