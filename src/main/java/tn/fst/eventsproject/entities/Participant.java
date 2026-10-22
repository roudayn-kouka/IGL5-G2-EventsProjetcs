package tn.fst.eventsproject.entities;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.*;
import lombok.experimental.FieldDefaults;

import javax.persistence.*;
import java.io.Serializable;
import java.util.Set;


@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE)
@Entity
public class Participant implements Serializable {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    int idPart;
    String nom;
    String prenom;
    @Enumerated(EnumType.STRING)
    Tache tache;
    @ManyToMany
    @JsonIgnoreProperties({"participants", "logistics"}) // évite la boucle JSON Participant -> Event -> Participant
    Set<Event> events;

}
