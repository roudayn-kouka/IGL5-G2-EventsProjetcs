package tn.fst.eventsproject.controllers;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import tn.fst.eventsproject.dto.EventDTO;
import tn.fst.eventsproject.dto.LogisticsDTO;
import tn.fst.eventsproject.dto.Mapper;
import tn.fst.eventsproject.dto.ParticipantDTO;
import tn.fst.eventsproject.services.IEventServices;

import java.time.LocalDate;
import java.util.List;

@RequiredArgsConstructor
@RequestMapping("event")
@RestController
public class EventRestController {
    private final IEventServices eventServices;

    @PostMapping("/addPart")
    public ParticipantDTO addParticipant(@RequestBody ParticipantDTO participant){
        return Mapper.toDto(eventServices.addParticipant(Mapper.toEntity(participant)));
    }
    @PostMapping("/addEvent/{id}")
    public EventDTO addEventPart(@RequestBody EventDTO event, @PathVariable("id") int idPart){
        return Mapper.toDto(eventServices.addAffectEvenParticipant(Mapper.toEntity(event), idPart));
    }
    @PostMapping("/addEvent")
    public EventDTO addEvent(@RequestBody EventDTO event){
        return Mapper.toDto(eventServices.addAffectEvenParticipant(Mapper.toEntity(event)));
    }
    @PutMapping("/addAffectLog/{description}")
    public LogisticsDTO addAffectLog(@RequestBody LogisticsDTO logistics,@PathVariable("description") String descriptionEvent){
        return Mapper.toDto(eventServices.addAffectLog(Mapper.toEntity(logistics),descriptionEvent));
    }
    @GetMapping("/getLogs/{d1}/{d2}")
    public List<LogisticsDTO> getLogistiquesDates (@PathVariable("d1") LocalDate date_debut, @PathVariable("d2") LocalDate date_fin){
        return Mapper.toLogisticsDtos(eventServices.getLogisticsDates(date_debut,date_fin));
    }
}
