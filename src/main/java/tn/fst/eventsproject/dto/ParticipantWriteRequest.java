package tn.fst.eventsproject.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;

import java.util.HashSet;
import java.util.Set;
import java.util.stream.Collectors;

@Getter
@Setter
@NoArgsConstructor
public class ParticipantWriteRequest {
    private int idPart;
    private String nom;
    private String prenom;
    private Tache tache;
    private Set<EventReference> events;

    public Participant toEntity() {
        Participant participant = new Participant();
        participant.setNom(nom);
        participant.setPrenom(prenom);
        participant.setTache(tache);
        if (events != null) {
            participant.setEvents(events.stream().map(EventReference::toEntity)
                    .collect(Collectors.toCollection(HashSet::new)));
        }
        return participant;
    }

    public Participant toReferenceEntity() {
        Participant participant = new Participant();
        participant.setIdPart(idPart);
        return participant;
    }

    @Getter
    @Setter
    @NoArgsConstructor
    public static class EventReference {
        private int idEvent;

        Event toEntity() {
            Event event = new Event();
            event.setIdEvent(idEvent);
            return event;
        }
    }
}
