package tn.fst.eventsproject.dto;

import lombok.*;
import tn.fst.eventsproject.entities.Tache;

import java.io.Serializable;
import java.time.LocalDate;
import java.util.Map;

/**
 * Résumé statistique d'un événement (renvoyé par l'API /event-stats).
 * On renvoie un DTO plutôt que l'entité Event pour éviter la récursion
 * JSON infinie Event -> participants -> events -> ...
 */
@Getter
@Setter
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class EventStatsDTO implements Serializable {

    private int idEvent;
    private String description;
    private LocalDate dateDebut;
    private LocalDate dateFin;

    /** Nombre de jours de l'événement (date de début et date de fin incluses). */
    private long dureeJours;

    /** Nombre total de participants affectés à l'événement. */
    private int nbParticipants;

    /** Répartition des participants par tâche (INVITE, ORGANISATEUR, ...). */
    private Map<Tache, Long> participantsParTache;

    /** Nombre total de logistiques liées à l'événement. */
    private int nbLogistics;

    /** Nombre de logistiques réservées. */
    private int nbLogisticsReservees;

    /** Coût des logistiques réservées : somme de prixUnit * quantite. */
    private float coutLogistiqueReservee;

    /** Average feedback rating; zero when no feedback exists. */
    private double averageRating;
}
