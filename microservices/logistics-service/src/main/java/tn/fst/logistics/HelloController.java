package tn.fst.logistics;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    @Value("${greeting:valeur par défaut}")
    private String greeting;

    @GetMapping("/hello")
    public String hello() {
        return greeting;
    }
}