package tn.fst.eventsproject.services;

import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;

import java.util.List;

public interface IParticipantServices {
    Participant addParticipant(Participant participant);
    List<Participant> getAllParticipants();
    Participant getParticipantById(int idPart);
    Participant updateParticipant(int idPart, Participant participant);
    void deleteParticipant(int idPart);
    Participant changeTache(int idPart, Tache tache);
}
