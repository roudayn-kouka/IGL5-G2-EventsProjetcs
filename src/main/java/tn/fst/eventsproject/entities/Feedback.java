package tn.fst.eventsproject.entities;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import javax.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "feedback", uniqueConstraints = @UniqueConstraint(
        name = "uk_feedback_event_participant", columnNames = {"event_id", "participant_id"}))
@Getter
@Setter
@NoArgsConstructor
public class Feedback {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @Column(nullable = false)
    private Integer note;

    @Lob
    private String commentaire;

    @Column(nullable = false, updatable = false)
    private Instant date;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "event_id", nullable = false)
    private Event event;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "participant_id", nullable = false)
    private Participant participant;

    @PrePersist
    private void timestamp() {
        if (date == null) {
            date = Instant.now();
        }
    }
}
