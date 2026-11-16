package tn.fst.logisticsclient.controllers;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import tn.fst.logisticsclient.dto.LogisticsDTO;
import tn.fst.logisticsclient.services.LogisticsResilientService;

@RestController
@RequestMapping("/client")
@RequiredArgsConstructor
public class ClientController {

    private final LogisticsResilientService service;

    @GetMapping("/logistics/{id}")
    public LogisticsDTO get(@PathVariable Integer id) {
        return service.getById(id);
    }

    @GetMapping("/faults/slow")
    public LogisticsDTO slow() { return service.slow(); }

    @GetMapping("/faults/corrupted")
    public LogisticsDTO corrupted() { return service.corrupted(); }

    @GetMapping("/faults/bad-url")
    public LogisticsDTO badUrl() { return service.badUrl(); }
}