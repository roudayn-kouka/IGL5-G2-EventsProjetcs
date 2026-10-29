package tn.fst.eventsproject.controllers;

import lombok.AccessLevel;
import lombok.RequiredArgsConstructor;
import lombok.experimental.FieldDefaults;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import tn.fst.eventsproject.dto.LogisticsDTO;
import tn.fst.eventsproject.dto.Mapper;
import tn.fst.eventsproject.services.ILogisticsService;

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
    public LogisticsDTO add(@RequestBody LogisticsDTO logistics) {
        return Mapper.toDto(logisticsService.addLogistics(Mapper.toEntity(logistics)));
    }

    // PUT /logistics
    @PutMapping
    public LogisticsDTO update(@RequestBody LogisticsDTO logistics) {
        return Mapper.toDto(logisticsService.updateLogistics(Mapper.toEntity(logistics)));
    }

    // DELETE /logistics/{id}
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable("id") int idLog) {
        logisticsService.deleteLogistics(idLog);
    }

    // GET /logistics/{id}
    @GetMapping("/{id}")
    public LogisticsDTO getById(@PathVariable("id") int idLog) {
        return Mapper.toDto(logisticsService.getLogisticsById(idLog));
    }

    // GET /logistics
    @GetMapping
    public List<LogisticsDTO> getAll() {
        return Mapper.toLogisticsDtos(logisticsService.getAllLogistics());
    }

    // GET /logistics/reserved
    @GetMapping("/reserved")
    public List<LogisticsDTO> getReserved() {
        return Mapper.toLogisticsDtos(logisticsService.getReservedLogistics());
    }

    // GET /logistics/{id}/cout
    @GetMapping("/{id}/cout")
    public float getCoutTotal(@PathVariable("id") int idLog) {
        return logisticsService.calculerCoutTotal(idLog);
    }
}