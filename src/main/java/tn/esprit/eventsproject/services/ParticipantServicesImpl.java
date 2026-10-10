package tn.esprit.eventsproject.services;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import tn.esprit.eventsproject.entities.Participant;
import tn.esprit.eventsproject.entities.Tache;
import tn.esprit.eventsproject.repositories.ParticipantRepository;

import java.util.List;

@Slf4j
@RequiredArgsConstructor
@Service
public class ParticipantServicesImpl implements IParticipantServices {

    private final ParticipantRepository participantRepository;

    @Override
    public Participant addParticipant(Participant participant) {
        return participantRepository.save(participant);
    }

    @Override
    public List<Participant> getAllParticipants() {
        return participantRepository.findAll();
    }

    @Override
    public Participant getParticipantById(int idPart) {
        return participantRepository.findById(idPart)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Participant not found with id " + idPart));
    }

    @Override
    public Participant updateParticipant(int idPart, Participant participant) {
        Participant existing = getParticipantById(idPart);
        existing.setNom(participant.getNom());
        existing.setPrenom(participant.getPrenom());
        existing.setTache(participant.getTache());
        return participantRepository.save(existing);
    }

    @Override
    public void deleteParticipant(int idPart) {
        Participant existing = getParticipantById(idPart);
        participantRepository.delete(existing);
        log.info("Participant {} deleted", idPart);
    }

    @Override
    public Participant changeTache(int idPart, Tache tache) {
        Participant existing = getParticipantById(idPart);
        existing.setTache(tache);
        return participantRepository.save(existing);
    }
}
