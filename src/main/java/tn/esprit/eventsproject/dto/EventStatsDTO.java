package tn.esprit.eventsproject.dto;

import lombok.*;
import lombok.experimental.FieldDefaults;
import tn.esprit.eventsproject.entities.Tache;

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
@FieldDefaults(level = AccessLevel.PRIVATE)
public class EventStatsDTO implements Serializable {

    int idEvent;
    String description;
    LocalDate dateDebut;
    LocalDate dateFin;

    /** Nombre de jours de l'événement (date de début et date de fin incluses). */
    long dureeJours;

    /** Nombre total de participants affectés à l'événement. */
    int nbParticipants;

    /** Répartition des participants par tâche (INVITE, ORGANISATEUR, ...). */
    Map<Tache, Long> participantsParTache;

    /** Nombre total de logistiques liées à l'événement. */
    int nbLogistics;

    /** Nombre de logistiques réservées. */
    int nbLogisticsReservees;

    /** Coût des logistiques réservées : somme de prixUnit * quantite. */
    float coutLogistiqueReservee;
}
