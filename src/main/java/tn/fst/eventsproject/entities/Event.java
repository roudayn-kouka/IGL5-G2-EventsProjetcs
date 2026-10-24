package tn.fst.eventsproject.entities;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.*;
import lombok.experimental.FieldDefaults;

import javax.persistence.*;
import java.io.Serializable;
import java.time.LocalDate;
import java.util.Set;

@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE)
@Entity
public class Event implements Serializable {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    int idEvent;
    String description;
    LocalDate dateDebut;
    LocalDate dateFin;
    float cout;
    @ManyToMany(mappedBy = "events")
    @JsonIgnoreProperties("events") // évite la boucle JSON Event -> Participant -> Event
    Set<Participant> participants;
    @OneToMany(fetch = FetchType.EAGER)
    Set<Logistics> logistics;

}
