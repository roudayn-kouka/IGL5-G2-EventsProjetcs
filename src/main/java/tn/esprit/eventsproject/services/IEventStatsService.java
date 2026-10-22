package tn.esprit.eventsproject.services;

import tn.esprit.eventsproject.dto.EventStatsDTO;

import java.time.LocalDate;
import java.util.List;

public interface IEventStatsService {

    /** Statistiques d'un événement donné (404 s'il n'existe pas). */
    EventStatsDTO getEventStats(int idEvent);

    /** Statistiques des événements à venir (dateDebut >= aujourd'hui), triés par date. */
    List<EventStatsDTO> getUpcomingEventsStats();

    /** Statistiques des événements dont la date de début est entre d1 et d2 (inclus). */
    List<EventStatsDTO> getEventsStatsBetween(LocalDate d1, LocalDate d2);
}
