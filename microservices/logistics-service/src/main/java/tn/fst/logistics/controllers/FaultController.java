package tn.fst.logistics.controllers;

import org.springframework.web.bind.annotation.*;
import tn.fst.logistics.entities.Logistics;

@RestController
@RequestMapping("/faults")
public class FaultController {

    @GetMapping("/slow")
    public Logistics slow() throws InterruptedException {
        Thread.sleep(6000);
        return new Logistics(1, "Reponse lente", true, 10f, 1);
    }

    @GetMapping("/corrupted")
    public Logistics corrupted() {
        return new Logistics(1, "Donnee corrompue", true, -50f, -3);
    }
}