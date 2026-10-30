package tn.fst.eventsproject.dto;

import lombok.*;
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
public class GlobalStatsDTO implements Serializable {

    private long nbEvents;
    private long nbEventsAVenir;
    private long nbParticipants;
    private long nbLogistics;
    private long nbLogisticsReservees;

    /** Pourcentage de logistiques réservées (0 -> 100). */
    private float tauxReservation;

    /** Somme prixUnit * quantite de toutes les logistiques réservées. */
    private float coutTotalLogistiqueReservee;

    /** Répartition de tous les participants par tâche. */
    private Map<Tache, Long> participantsParTache;
}
