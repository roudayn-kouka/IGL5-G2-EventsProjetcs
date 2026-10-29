package tn.fst.eventsproject.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Data;
import tn.fst.eventsproject.entities.Tache;

import java.util.Set;

@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ParticipantDTO {
    private int idPart;
    private String nom;
    private String prenom;
    private Tache tache;
    private Set<EventDTO> events;
}
