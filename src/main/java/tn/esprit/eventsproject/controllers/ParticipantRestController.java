package tn.esprit.eventsproject.controllers;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import tn.esprit.eventsproject.entities.Participant;
import tn.esprit.eventsproject.entities.Tache;
import tn.esprit.eventsproject.services.IParticipantServices;

import java.util.List;

@RequiredArgsConstructor
@RequestMapping("participant")
@RestController
public class ParticipantRestController {

    private final IParticipantServices participantServices;

    @PostMapping("/add")
    public Participant addParticipant(@RequestBody Participant participant) {
        return participantServices.addParticipant(participant);
    }

    @GetMapping("/all")
    public List<Participant> getAllParticipants() {
        return participantServices.getAllParticipants();
    }

    @GetMapping("/{id}")
    public Participant getParticipant(@PathVariable("id") int idPart) {
        return participantServices.getParticipantById(idPart);
    }

    @PutMapping("/update/{id}")
    public Participant updateParticipant(@PathVariable("id") int idPart,
                                         @RequestBody Participant participant) {
        return participantServices.updateParticipant(idPart, participant);
    }

    @PutMapping("/{id}/tache/{tache}")
    public Participant changeTache(@PathVariable("id") int idPart,
                                   @PathVariable("tache") Tache tache) {
        return participantServices.changeTache(idPart, tache);
    }

    @DeleteMapping("/delete/{id}")
    public void deleteParticipant(@PathVariable("id") int idPart) {
        participantServices.deleteParticipant(idPart);
    }
}
