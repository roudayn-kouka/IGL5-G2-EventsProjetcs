package tn.fst.eventsproject.controllers;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import tn.fst.eventsproject.dto.Mapper;
import tn.fst.eventsproject.dto.ParticipantDTO;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.services.IParticipantServices;

import java.util.List;

@RequiredArgsConstructor
@RequestMapping("participant")
@RestController
public class ParticipantRestController {

    private final IParticipantServices participantServices;

    @PostMapping("/add")
    public ParticipantDTO addParticipant(@RequestBody ParticipantDTO participant) {
        return Mapper.toDto(participantServices.addParticipant(Mapper.toEntity(participant)));
    }

    @GetMapping("/all")
    public List<ParticipantDTO> getAllParticipants() {
        return Mapper.toParticipantDtos(participantServices.getAllParticipants());
    }

    @GetMapping("/{id}")
    public ParticipantDTO getParticipant(@PathVariable("id") int idPart) {
        return Mapper.toDto(participantServices.getParticipantById(idPart));
    }

    @PutMapping("/update/{id}")
    public ParticipantDTO updateParticipant(@PathVariable("id") int idPart,
                                            @RequestBody ParticipantDTO participant) {
        return Mapper.toDto(participantServices.updateParticipant(idPart, Mapper.toEntity(participant)));
    }

    @PutMapping("/{id}/tache/{tache}")
    public ParticipantDTO changeTache(@PathVariable("id") int idPart,
                                      @PathVariable("tache") Tache tache) {
        return Mapper.toDto(participantServices.changeTache(idPart, tache));
    }

    @DeleteMapping("/delete/{id}")
    public void deleteParticipant(@PathVariable("id") int idPart) {
        participantServices.deleteParticipant(idPart);
    }
}
