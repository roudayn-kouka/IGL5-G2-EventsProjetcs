package tn.fst.eventsproject.dto;

import lombok.*;
import lombok.experimental.FieldDefaults;
import tn.fst.eventsproject.entities.Tache;

import java.io.Serializable;
import java.util.Map;

/**
 * Indicateurs globaux affichés en haut du dashboard (GET /event-stats/summary).
 */
@Getter
@Setter
@Builder
@AllArgsConstructor
@NoArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE)
public class GlobalStatsDTO implements Serializable {

    long nbEvents;
    long nbEventsAVenir;
    long nbParticipants;
    long nbLogistics;
    long nbLogisticsReservees;

    /** Pourcentage de logistiques réservées (0 -> 100). */
    float tauxReservation;

    /** Somme prixUnit * quantite de toutes les logistiques réservées. */
    float coutTotalLogistiqueReservee;

    /** Répartition de tous les participants par tâche. */
    Map<Tache, Long> participantsParTache;
}
