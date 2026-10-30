package tn.fst.eventsproject.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import tn.fst.eventsproject.entities.Event;

import java.time.LocalDate;
import java.util.HashSet;
import java.util.Set;
import java.util.stream.Collectors;

@Getter
@Setter
@NoArgsConstructor
public class EventWriteRequest {
    private int idEvent;
    private String description;
    private LocalDate dateDebut;
    private LocalDate dateFin;
    private float cout;
    private Set<ParticipantWriteRequest> participants;
    private Set<LogisticsWriteRequest> logistics;

    public Event toEntity() {
        Event event = new Event();
        event.setIdEvent(idEvent);
        event.setDescription(description);
        event.setDateDebut(dateDebut);
        event.setDateFin(dateFin);
        event.setCout(cout);
        if (participants != null) {
            event.setParticipants(participants.stream().map(ParticipantWriteRequest::toReferenceEntity)
                    .collect(Collectors.toCollection(HashSet::new)));
        }
        if (logistics != null) {
            event.setLogistics(logistics.stream().map(LogisticsWriteRequest::toEntity)
                    .collect(Collectors.toCollection(HashSet::new)));
        }
        return event;
    }
}
