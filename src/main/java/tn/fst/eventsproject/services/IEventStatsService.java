package tn.fst.eventsproject.services;

import tn.fst.eventsproject.dto.EventStatsDTO;
import tn.fst.eventsproject.dto.GlobalStatsDTO;

import java.time.LocalDate;
import java.util.List;

public interface IEventStatsService {

    /** Statistiques d'un événement donné (404 s'il n'existe pas). */
    EventStatsDTO getEventStats(int idEvent);

    /** Statistiques de tous les événements, triés par date de début. */
    List<EventStatsDTO> getAllEventsStats();

    /** Statistiques des événements à venir (dateDebut >= aujourd'hui), triés par date. */
    List<EventStatsDTO> getUpcomingEventsStats();

    /** Statistiques des événements dont la date de début est entre d1 et d2 (inclus). */
    List<EventStatsDTO> getEventsStatsBetween(LocalDate d1, LocalDate d2);

    /** Indicateurs globaux pour le dashboard. */
    GlobalStatsDTO getGlobalStats();
}
