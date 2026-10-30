package tn.fst.eventsproject.entities;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.*;

import javax.persistence.*;
import java.io.Serializable;
import java.time.LocalDate;
import java.util.Set;

@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@Entity
public class Event implements Serializable {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private int idEvent;
    private String description;
    private LocalDate dateDebut;
    private LocalDate dateFin;
    private float cout;
    @ManyToMany(mappedBy = "events")
    @JsonIgnoreProperties("events") // évite la boucle JSON Event -> Participant -> Event
    private Set<Participant> participants;
    @OneToMany(fetch = FetchType.EAGER)
    private Set<Logistics> logistics;

}
