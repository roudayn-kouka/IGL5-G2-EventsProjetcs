package tn.fst.logistics.controllers;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class InstanceController {

    @Value("${server.port}")
    private String port;

    @GetMapping("/instance")
    public String instance() {
        return "logistics-service sur le port " + port;
    }
}