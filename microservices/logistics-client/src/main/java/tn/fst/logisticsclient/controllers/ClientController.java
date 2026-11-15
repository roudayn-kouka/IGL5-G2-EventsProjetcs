package tn.fst.logisticsclient.controllers;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import tn.fst.logisticsclient.dto.LogisticsDTO;
import tn.fst.logisticsclient.services.LogisticsResilientService;

@RestController
@RequestMapping("/client/logistics")
@RequiredArgsConstructor
public class ClientController {

    private final LogisticsResilientService service;

    @GetMapping("/{id}")
    public LogisticsDTO get(@PathVariable Integer id) {
        return service.getById(id);
    }
}