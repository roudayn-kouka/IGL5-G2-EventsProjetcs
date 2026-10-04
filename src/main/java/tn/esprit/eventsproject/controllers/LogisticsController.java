package tn.esprit.eventsproject.controllers;

import lombok.AccessLevel;
import lombok.RequiredArgsConstructor;
import lombok.experimental.FieldDefaults;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import tn.esprit.eventsproject.entities.Logistics;
import tn.esprit.eventsproject.services.ILogisticsService;

import java.util.List;

@RestController
@RequestMapping("/logistics")
@RequiredArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE, makeFinal = true)
public class LogisticsController {

    ILogisticsService logisticsService;

    // POST /logistics
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Logistics add(@RequestBody Logistics logistics) {
        return logisticsService.addLogistics(logistics);
    }

    // PUT /logistics
    @PutMapping
    public Logistics update(@RequestBody Logistics logistics) {
        return logisticsService.updateLogistics(logistics);
    }

    // DELETE /logistics/{id}
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable("id") int idLog) {
        logisticsService.deleteLogistics(idLog);
    }

    // GET /logistics/{id}
    @GetMapping("/{id}")
    public Logistics getById(@PathVariable("id") int idLog) {
        return logisticsService.getLogisticsById(idLog);
    }

    // GET /logistics
    @GetMapping
    public List<Logistics> getAll() {
        return logisticsService.getAllLogistics();
    }

    // GET /logistics/reserved
    @GetMapping("/reserved")
    public List<Logistics> getReserved() {
        return logisticsService.getReservedLogistics();
    }

    // GET /logistics/{id}/cout
    @GetMapping("/{id}/cout")
    public float getCoutTotal(@PathVariable("id") int idLog) {
        return logisticsService.calculerCoutTotal(idLog);
    }
}