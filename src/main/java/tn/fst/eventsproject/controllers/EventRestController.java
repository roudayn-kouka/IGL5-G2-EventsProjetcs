package tn.fst.eventsproject.controllers;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.dto.EventWriteRequest;
import tn.fst.eventsproject.dto.LogisticsWriteRequest;
import tn.fst.eventsproject.dto.ParticipantWriteRequest;
import tn.fst.eventsproject.services.IEventServices;

import java.time.LocalDate;
import java.util.List;

@RequiredArgsConstructor
@RequestMapping("event")
@RestController
public class EventRestController {
    private final IEventServices eventServices;

    @PostMapping("/addPart")
    public Participant addParticipant(@RequestBody ParticipantWriteRequest participant){
        return eventServices.addParticipant(participant.toEntity());
    }
    @PostMapping("/addEvent/{id}")
    public Event addEventPart(@RequestBody EventWriteRequest event, @PathVariable("id") int idPart){
        return eventServices.addAffectEvenParticipant(event.toEntity(), idPart);
    }
    @PostMapping("/addEvent")
    public Event addEvent(@RequestBody EventWriteRequest event){
        return eventServices.addAffectEvenParticipant(event.toEntity());
    }
    @PutMapping("/addAffectLog/{description}")
    public Logistics addAffectLog(@RequestBody LogisticsWriteRequest logistics,@PathVariable("description") String descriptionEvent){
        return eventServices.addAffectLog(logistics.toEntity(),descriptionEvent);
    }
    @GetMapping("/getLogs/{d1}/{d2}")
    public List<Logistics> getLogistiquesDates(@PathVariable("d1") LocalDate dateDebut,
                                              @PathVariable("d2") LocalDate dateFin){
        return eventServices.getLogisticsDates(dateDebut, dateFin);
    }
}
