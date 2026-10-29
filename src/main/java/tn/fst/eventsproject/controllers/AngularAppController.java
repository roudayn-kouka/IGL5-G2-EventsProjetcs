package tn.fst.eventsproject.controllers;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * Serve Angular from the Spring Boot JAR at /events/app/.
 * /events is the servlet context-path, so it is not included in these mappings.
 */
@Controller
public class AngularAppController {

    @GetMapping({"/app", "/app/"})
    public String index() {
        return "forward:/app/index.html";
    }
}
