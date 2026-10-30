package tn.fst.eventsproject.entities;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.*;

import javax.persistence.*;
import java.io.Serializable;
import java.util.Set;


@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@Entity
public class Participant implements Serializable {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private int idPart;
    private String nom;
    private String prenom;
    @Enumerated(EnumType.STRING)
    private Tache tache;
    @ManyToMany
    @JsonIgnoreProperties({"participants", "logistics"}) // évite la boucle JSON Participant -> Event -> Participant
    private Set<Event> events;

}
